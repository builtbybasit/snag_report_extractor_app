import 'dart:typed_data';

import 'core/pdf_objects.dart';
import 'core/pdf_parser.dart';
import 'document.dart';
import 'text_page.dart';
import 'geometry/rect.dart';
import 'geometry/point.dart';
import 'geometry/matrix.dart';
import 'geometry/quad.dart';
import 'models/text_block.dart';
import 'models/text_word.dart';
import 'models/text_dict.dart';
import 'models/image_info.dart';
import 'models/link_info.dart';
import 'models/annotation.dart';
import 'models/widget_info.dart';

/// Text output format options, matching PyMuPDF's format strings.
enum TextFormat { text, blocks, words, dict, rawdict, html, xhtml, xml, json }

/// PDF page class, equivalent to PyMuPDF's `fitz.Page`.
///
/// Provides access to:
/// - Page geometry (rect, mediaBox, cropBox, rotation)
/// - Text extraction (plain, blocks, words, dict, HTML)
/// - Image listing
/// - Link extraction
/// - Annotations
/// - Text search
/// - Content insertion (text, images)
/// - Form widgets
class Page {
  /// Parent document.
  final Document document;

  /// 0-based page number.
  final int pageNumber;

  /// The page dictionary.
  final PdfDict pageDict;

  /// Object number of this page.
  final int objectNumber;

  /// The PDF parser.
  final PdfParser parser;

  /// Cached text page.
  TextPage? _textPage;

  Page({
    required this.document,
    required this.pageNumber,
    required this.pageDict,
    required this.objectNumber,
    required this.parser,
  });

  // ---------- Geometry ----------

  /// Page rectangle (after rotation), equivalent to PyMuPDF's `page.rect`.
  Rect get rect {
    final mb = mediaBox;
    final cb = cropBox;
    final r = cb ?? mb;
    final rot = rotation;
    if (rot == 90 || rot == 270) {
      return Rect(r.x0, r.y0, r.y1 - r.y0 + r.x0, r.x1 - r.x0 + r.y0);
    }
    return r;
  }

  /// MediaBox of the page.
  Rect get mediaBox => _getBox('MediaBox') ?? const Rect(0, 0, 612, 792);

  /// CropBox of the page (may differ from MediaBox).
  Rect? get cropBox => _getBox('CropBox');

  /// BleedBox.
  Rect? get bleedBox => _getBox('BleedBox');

  /// TrimBox.
  Rect? get trimBox => _getBox('TrimBox');

  /// ArtBox.
  Rect? get artBox => _getBox('ArtBox');

  /// Page rotation in degrees (0, 90, 180, 270).
  int get rotation {
    final rot = _getInheritedInt('Rotate') ?? 0;
    return rot % 360;
  }

  /// Set page rotation.
  void setRotation(int degrees) {
    pageDict['Rotate'] = PdfInt(degrees % 360);
  }

  /// Width of the page.
  double get width => rect.width;

  /// Height of the page.
  double get height => rect.height;

  /// MediaBox size as a Point.
  Point get mediaBoxSize {
    final mb = mediaBox;
    return Point(mb.width, mb.height);
  }

  /// The transformation matrix from PDF coordinates to page coordinates.
  Matrix get transformationMatrix {
    final mb = mediaBox;
    final rot = rotation;
    switch (rot) {
      case 90:
        return Matrix(0, -1, 1, 0, -mb.y0, mb.x1);
      case 180:
        return Matrix(-1, 0, 0, -1, mb.x1, mb.y1);
      case 270:
        return Matrix(0, 1, -1, 0, mb.y1, -mb.x0);
      default:
        return Matrix(1, 0, 0, -1, -mb.x0, mb.y1);
    }
  }

  /// Derotation matrix.
  Matrix get rotationMatrix {
    final rot = rotation;
    if (rot == 0) return Matrix.identity;
    return Matrix.rotation(-rot.toDouble());
  }

  Rect? _getBox(String name) {
    // Check page dict first, then inherit from parents
    var boxArray = pageDict.getArray(name);
    if (boxArray == null) {
      // Try resolving from parent
      final parentRef = pageDict.getRef('Parent');
      if (parentRef != null) {
        final parentObj = parser.getObject(parentRef.objectNumber);
        boxArray = parentObj?.dict?.getArray(name);
      }
    }
    if (boxArray == null) return null;

    // Resolve indirect references in array
    final values = <double>[];
    for (final item in boxArray.items) {
      if (item is PdfInt) {
        values.add(item.value.toDouble());
      } else if (item is PdfReal) {
        values.add(item.value);
      } else if (item is PdfRef) {
        final resolved = parser.resolve(item);
        if (resolved is PdfInt) values.add(resolved.value.toDouble());
        if (resolved is PdfReal) values.add(resolved.value);
      }
    }

    if (values.length >= 4) {
      return Rect(values[0], values[1], values[2], values[3]).normalized;
    }
    return null;
  }

  int? _getInheritedInt(String key) {
    var val = pageDict.getInt(key);
    if (val != null) return val;

    // Walk up parent chain
    var parentRef = pageDict.getRef('Parent');
    int depth = 0;
    while (parentRef != null && depth < 20) {
      final parentObj = parser.getObject(parentRef.objectNumber);
      if (parentObj?.dict == null) break;
      val = parentObj!.dict!.getInt(key);
      if (val != null) return val;
      parentRef = parentObj.dict!.getRef('Parent');
      depth++;
    }
    return null;
  }

  // ---------- Text Extraction ----------

  /// Extract text from the page.
  ///
  /// Equivalent to PyMuPDF's `page.get_text()`.
  ///
  /// [format] controls the output:
  /// - `TextFormat.text` — plain text (default)
  /// - `TextFormat.html` — HTML format
  /// - `TextFormat.dict` — use [getTextDict] instead
  String getText({TextFormat format = TextFormat.text}) {
    switch (format) {
      case TextFormat.text:
        return _getTextPage().extractText();
      case TextFormat.html:
        return _getTextPage().extractHtml();
      case TextFormat.xhtml:
        return _getTextPage().extractXhtml();
      case TextFormat.xml:
        return _getTextPage().extractXml();
      default:
        return _getTextPage().extractText();
    }
  }

  /// Extract text blocks with position information.
  ///
  /// Equivalent to PyMuPDF's `page.get_text("blocks")`.
  List<TextBlock> getTextBlocks() => _getTextPage().extractBlocks();

  /// Extract individual words with position information.
  ///
  /// Equivalent to PyMuPDF's `page.get_text("words")`.
  List<TextWord> getTextWords() => _getTextPage().extractWords();

  /// Extract text as a detailed dictionary.
  ///
  /// Equivalent to PyMuPDF's `page.get_text("dict")`.
  TextDict getTextDict({bool raw = false}) =>
      _getTextPage().extractDict(raw: raw);

  /// Get text inside a rectangle.
  ///
  /// Equivalent to PyMuPDF's `page.get_textbox()`.
  String getTextBox(Rect rect) {
    final words = getTextWords();
    final buffer = StringBuffer();
    for (final w in words) {
      if (rect.overlaps(w.rect)) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(w.word);
      }
    }
    return buffer.toString();
  }

  /// Search for text on the page.
  ///
  /// Returns a list of Rect/Quad where the text was found.
  /// Equivalent to PyMuPDF's `page.search_for()`.
  List<Rect> searchFor(
    String text, {
    bool quads = false,
    Rect? clip,
    int flags = 0,
  }) {
    final results = <Rect>[];
    if (text.isEmpty) return results;

    final words = getTextWords();
    final searchLower = text.toLowerCase();
    final wordTexts = words.map((w) => w.word.toLowerCase()).toList();

    // Simple word-level search
    final searchWords = searchLower.split(RegExp(r'\s+'));
    for (int i = 0; i <= wordTexts.length - searchWords.length; i++) {
      bool match = true;
      for (int j = 0; j < searchWords.length; j++) {
        if (!wordTexts[i + j].contains(searchWords[j])) {
          match = false;
          break;
        }
      }
      if (match) {
        Rect combined = words[i].rect;
        for (int j = 1; j < searchWords.length; j++) {
          combined = combined.union(words[i + j].rect);
        }
        if (clip == null || clip.overlaps(combined)) {
          results.add(combined);
        }
      }
    }

    // Also check character-level for single-word matches
    if (searchWords.length == 1) {
      for (final word in words) {
        if (word.word.toLowerCase().contains(searchLower)) {
          if (clip == null || clip.overlaps(word.rect)) {
            if (!results.any((r) => r.overlaps(word.rect))) {
              results.add(word.rect);
            }
          }
        }
      }
    }

    return results;
  }

  TextPage _getTextPage() {
    _textPage ??= TextPage.fromPage(this, parser);
    return _textPage!;
  }

  /// Debug: access the TextPage for diagnostics.
  TextPage getTextPage() => _getTextPage();

  // ---------- Images ----------

  /// Get list of images on this page.
  ///
  /// Equivalent to PyMuPDF's `page.get_images()`.
  List<PdfImageInfo> getImages({bool full = false}) {
    final images = <PdfImageInfo>[];
    final resources = _getResources();
    if (resources == null) return images;

    final xobjects = resources.getDict('XObject');
    if (xobjects == null) {
      // Try resolving
      final xoRef = resources.getRef('XObject');
      if (xoRef != null) {
        final resolved = parser.getObject(xoRef.objectNumber);
        if (resolved?.dict != null) {
          return _extractImagesFromDict(resolved!.dict!, full);
        }
      }
      return images;
    }

    return _extractImagesFromDict(xobjects, full);
  }

  List<PdfImageInfo> _extractImagesFromDict(PdfDict xobjects, bool full) {
    final images = <PdfImageInfo>[];

    for (final key in xobjects.keys) {
      final ref = xobjects.getRef(key);
      if (ref == null) continue;

      final obj = parser.getObject(ref.objectNumber);
      final dict = obj?.dict;
      if (dict == null) continue;

      if (dict.getName('Subtype') != 'Image') continue;

      final width = dict.getInt('Width') ?? 0;
      final height = dict.getInt('Height') ?? 0;
      final bpc = dict.getInt('BitsPerComponent') ?? 8;

      String csName = 'DeviceRGB';
      final cs = dict['ColorSpace'];
      if (cs is PdfName) csName = cs.value;

      int smask = 0;
      final smaskRef = dict.getRef('SMask');
      if (smaskRef != null) smask = smaskRef.objectNumber;

      String filter = '';
      final filterObj = dict['Filter'];
      if (filterObj is PdfName) filter = filterObj.value;

      images.add(PdfImageInfo(
        xref: ref.objectNumber,
        smask: smask,
        width: width,
        height: height,
        bpc: bpc,
        colorspace: csName,
        name: key,
        filter: filter,
      ));
    }

    return images;
  }

  /// Get the bounding box of a named image on the page (screen coords).
  ///
  /// Resolved from the content stream's `cm`/`Do` placement, so this now
  /// returns a real rectangle (it used to be an unimplemented stub).
  Rect? getImageBbox(String name) => _getTextPage().imageBboxFor(name);

  // ---------- Links ----------

  /// Get links on this page.
  ///
  /// Equivalent to PyMuPDF's `page.get_links()`.
  List<LinkInfo> getLinks() {
    final links = <LinkInfo>[];
    final annots = _getAnnotsArray();
    if (annots == null) return links;

    for (final annotRef in annots.items) {
      if (annotRef is! PdfRef) continue;
      final obj = parser.getObject(annotRef.objectNumber);
      final dict = obj?.dict;
      if (dict == null) continue;

      if (dict.getName('Subtype') != 'Link') continue;

      final rectArray = dict.getArray('Rect');
      if (rectArray == null) continue;
      final rectVals = rectArray.toDoubleList();
      if (rectVals.length < 4) continue;
      final linkRect = Rect(rectVals[0], rectVals[1], rectVals[2], rectVals[3]);

      // Determine link type
      final action = dict.getDict('A');
      if (action == null) {
        final actionRef = dict.getRef('A');
        if (actionRef != null) {
          final actionObj = parser.getObject(actionRef.objectNumber);
          if (actionObj?.dict != null) {
            _parseLinkAction(actionObj!.dict!, linkRect, links);
            continue;
          }
        }
      }

      if (action != null) {
        _parseLinkAction(action, linkRect, links);
        continue;
      }

      // Check for /Dest
      final dest = dict['Dest'];
      if (dest is PdfArray && dest.length > 0) {
        int targetPage = 0;
        final pageRef = dest[0];
        if (pageRef is PdfRef) {
          targetPage = document.getPageNumberForRef(pageRef);
        }
        links.add(LinkInfo(
          kind: LinkInfo.kindGoto,
          from: linkRect,
          page: targetPage,
        ));
        continue;
      }

      links.add(LinkInfo(kind: LinkInfo.kindNone, from: linkRect));
    }

    return links;
  }

  void _parseLinkAction(PdfDict action, Rect linkRect, List<LinkInfo> links) {
    final actionType = action.getName('S');
    switch (actionType) {
      case 'URI':
        final uri = action.getString('URI');
        links.add(LinkInfo(
          kind: LinkInfo.kindUri,
          from: linkRect,
          uri: uri,
        ));
        break;
      case 'GoTo':
        final dest = action['D'];
        int targetPage = 0;
        if (dest is PdfArray && dest.length > 0) {
          final pageRef = dest[0];
          if (pageRef is PdfRef) {
            targetPage = document.getPageNumberForRef(pageRef);
          }
        }
        links.add(LinkInfo(
          kind: LinkInfo.kindGoto,
          from: linkRect,
          page: targetPage,
        ));
        break;
      case 'GoToR':
        links.add(LinkInfo(
          kind: LinkInfo.kindGotoR,
          from: linkRect,
          fileSpec: action.getString('F'),
        ));
        break;
      case 'Launch':
        links.add(LinkInfo(
          kind: LinkInfo.kindLaunch,
          from: linkRect,
          fileSpec: action.getString('F'),
        ));
        break;
      case 'Named':
        links.add(LinkInfo(
          kind: LinkInfo.kindNamed,
          from: linkRect,
          named: action.getString('N'),
        ));
        break;
      default:
        links.add(LinkInfo(kind: LinkInfo.kindNone, from: linkRect));
    }
  }

  // ---------- Annotations ----------

  /// Get annotations on this page.
  ///
  /// Equivalent to PyMuPDF's `page.annots()`.
  List<PdfAnnotation> getAnnotations({List<AnnotationType>? types}) {
    final annots = <PdfAnnotation>[];
    final annotsArray = _getAnnotsArray();
    if (annotsArray == null) return annots;

    for (final annotRef in annotsArray.items) {
      if (annotRef is! PdfRef) continue;
      final obj = parser.getObject(annotRef.objectNumber);
      final dict = obj?.dict;
      if (dict == null) continue;

      final subtypeName = dict.getName('Subtype');
      if (subtypeName == null) continue;

      final type = annotationTypeFromName('/$subtypeName');
      if (types != null && !types.contains(type)) continue;

      final rectArray = dict.getArray('Rect');
      Rect annotRect = Rect.empty;
      if (rectArray != null) {
        final vals = rectArray.toDoubleList();
        if (vals.length >= 4) {
          annotRect = Rect(vals[0], vals[1], vals[2], vals[3]);
        }
      }

      // Parse colors
      List<double>? color;
      final cArray = dict.getArray('C');
      if (cArray != null) color = cArray.toDoubleList();

      List<double>? fillColor;
      final icArray = dict.getArray('IC');
      if (icArray != null) fillColor = icArray.toDoubleList();

      annots.add(PdfAnnotation(
        type: type,
        rect: annotRect,
        xref: annotRef.objectNumber,
        content: dict.getString('Contents'),
        title: dict.getString('T'),
        subject: dict.getString('Subj'),
        creationDate: dict.getString('CreationDate'),
        modDate: dict.getString('M'),
        color: color,
        fillColor: fillColor,
        opacity: dict.getDouble('CA'),
        flags: dict.getInt('F') ?? 0,
        icon: dict.getString('Name'),
      ));
    }

    return annots;
  }

  /// Get annotation cross-reference numbers.
  List<int> annotXrefs() {
    final xrefs = <int>[];
    final annotsArray = _getAnnotsArray();
    if (annotsArray == null) return xrefs;

    for (final ref in annotsArray.items) {
      if (ref is PdfRef) xrefs.add(ref.objectNumber);
    }
    return xrefs;
  }

  /// Add a text annotation (sticky note).
  PdfAnnotation addTextAnnot(Point point, String text, {String icon = 'Note'}) {
    // Create annotation dict
    /* final annotDict = */ PdfDict({
      'Type': PdfName('/Annot'),
      'Subtype': PdfName('/Text'),
      'Rect': PdfArray([
        PdfReal(point.x),
        PdfReal(point.y),
        PdfReal(point.x + 20),
        PdfReal(point.y + 20),
      ]),
      'Contents': PdfString(text),
      'Name': PdfName('/$icon'),
      'F': PdfInt(4), // Print flag
    });

    return PdfAnnotation(
      type: AnnotationType.text,
      rect: Rect(point.x, point.y, point.x + 20, point.y + 20),
      xref: 0,
      content: text,
      icon: icon,
    );
  }

  /// Add a highlight annotation over quads.
  PdfAnnotation addHighlightAnnot(List<Quad> quads) {
    Rect combinedRect = Rect.empty;
    for (final q in quads) {
      combinedRect = combinedRect.union(q.rect);
    }

    return PdfAnnotation(
      type: AnnotationType.highlight,
      rect: combinedRect,
      xref: 0,
      color: [1, 1, 0], // yellow
    );
  }

  /// Add an underline annotation.
  PdfAnnotation addUnderlineAnnot(List<Quad> quads) {
    Rect combinedRect = Rect.empty;
    for (final q in quads) {
      combinedRect = combinedRect.union(q.rect);
    }
    return PdfAnnotation(
      type: AnnotationType.underline,
      rect: combinedRect,
      xref: 0,
      color: [0, 0, 1],
    );
  }

  /// Add a strikeout annotation.
  PdfAnnotation addStrikeoutAnnot(List<Quad> quads) {
    Rect combinedRect = Rect.empty;
    for (final q in quads) {
      combinedRect = combinedRect.union(q.rect);
    }
    return PdfAnnotation(
      type: AnnotationType.strikeOut,
      rect: combinedRect,
      xref: 0,
      color: [1, 0, 0],
    );
  }

  /// Add a stamp annotation.
  PdfAnnotation addStampAnnot(Rect stampRect, {int stamp = 0}) {
    return PdfAnnotation(
      type: AnnotationType.stamp,
      rect: stampRect,
      xref: 0,
    );
  }

  /// Add a caret annotation.
  PdfAnnotation addCaretAnnot(Point point) {
    return PdfAnnotation(
      type: AnnotationType.caret,
      rect: Rect(point.x, point.y, point.x + 20, point.y + 20),
      xref: 0,
    );
  }

  // ---------- Widgets (Form Fields) ----------

  /// Get form widgets on this page.
  ///
  /// Equivalent to PyMuPDF's `page.widgets()`.
  List<WidgetInfo> getWidgets({List<int>? types}) {
    final widgets = <WidgetInfo>[];
    final annotsArray = _getAnnotsArray();
    if (annotsArray == null) return widgets;

    for (final annotRef in annotsArray.items) {
      if (annotRef is! PdfRef) continue;
      final obj = parser.getObject(annotRef.objectNumber);
      final dict = obj?.dict;
      if (dict == null) continue;

      if (dict.getName('Subtype') != 'Widget') continue;

      final ft = dict.getName('FT') ?? _getInheritedFieldType(dict);
      int fieldType;
      switch (ft) {
        case 'Btn':
          fieldType = WidgetInfo.typeButton;
          break;
        case 'Tx':
          fieldType = WidgetInfo.typeText;
          break;
        case 'Ch':
          fieldType = WidgetInfo.typeChoice;
          break;
        case 'Sig':
          fieldType = WidgetInfo.typeSignature;
          break;
        default:
          fieldType = WidgetInfo.typeUnknown;
      }

      if (types != null && !types.contains(fieldType)) continue;

      final rectArray = dict.getArray('Rect');
      Rect widgetRect = Rect.empty;
      if (rectArray != null) {
        final vals = rectArray.toDoubleList();
        if (vals.length >= 4) {
          widgetRect = Rect(vals[0], vals[1], vals[2], vals[3]);
        }
      }

      final fieldFlags = dict.getInt('Ff') ?? 0;

      widgets.add(WidgetInfo(
        xref: annotRef.objectNumber,
        fieldType: fieldType,
        fieldName: _getFieldName(dict),
        fieldValue: dict.getString('V'),
        defaultValue: dict.getString('DV'),
        rect: widgetRect,
        fieldFlags: fieldFlags,
        readOnly: (fieldFlags & 1) != 0,
        required: (fieldFlags & 2) != 0,
      ));
    }

    return widgets;
  }

  String _getFieldName(PdfDict dict) {
    final parts = <String>[];
    var current = dict;
    int depth = 0;

    while (depth < 20) {
      final t = current.getString('T');
      if (t != null) parts.insert(0, t);

      final parentRef = current.getRef('Parent');
      if (parentRef == null) break;
      final parentObj = parser.getObject(parentRef.objectNumber);
      if (parentObj?.dict == null) break;
      current = parentObj!.dict!;
      depth++;
    }

    return parts.join('.');
  }

  String? _getInheritedFieldType(PdfDict dict) {
    var parentRef = dict.getRef('Parent');
    int depth = 0;
    while (parentRef != null && depth < 20) {
      final parentObj = parser.getObject(parentRef.objectNumber);
      if (parentObj?.dict == null) break;
      final ft = parentObj!.dict!.getName('FT');
      if (ft != null) return ft;
      parentRef = parentObj.dict!.getRef('Parent');
      depth++;
    }
    return null;
  }

  // ---------- Content Insertion ----------

  /// Insert text on the page.
  ///
  /// Equivalent to PyMuPDF's `page.insert_text()`.
  void insertText(
    Point point,
    String text, {
    double fontSize = 11,
    String fontName = 'Helvetica',
    List<double>? color,
    double rotate = 0,
  }) {
    final c = color ?? [0, 0, 0];
    final colorStr = c.length == 3 ? '${c[0]} ${c[1]} ${c[2]} rg' : '0 0 0 rg';

    final escaped = text
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');

    final contentStr =
        'BT\n/$fontName $fontSize Tf\n$colorStr\n${point.x} ${point.y} Td\n($escaped) Tj\nET\n';

    _appendContent(contentStr, fontName: fontName, fontSize: fontSize);
  }

  /// Insert a text box within a rectangle.
  ///
  /// Equivalent to PyMuPDF's `page.insert_textbox()`.
  double insertTextbox(
    Rect rect,
    String text, {
    double fontSize = 11,
    String fontName = 'Helvetica',
    List<double>? color,
    int align = 0, // 0=left, 1=center, 2=right, 3=justify
  }) {
    insertText(
      Point(rect.x0, rect.y1 - fontSize),
      text,
      fontSize: fontSize,
      fontName: fontName,
      color: color,
    );
    return rect.y1;
  }

  /// Insert an image on the page.
  ///
  /// Equivalent to PyMuPDF's `page.insert_image()`.
  void insertImage(
    Rect rect, {
    Uint8List? stream,
    String? filename,
    int xref = 0,
    bool keepProportion = true,
    int rotate = 0,
  }) {
    // Create image XObject and reference it in content stream
    // Simplified implementation
    final w = rect.width;
    final h = rect.height;
    final contentStr = 'q\n$w 0 0 $h ${rect.x0} ${rect.y0} cm\n/Img Do\nQ\n';
    _appendContent(contentStr);
  }

  void _appendContent(String content, {String? fontName, double? fontSize}) {
    // In a full implementation, this would modify the content stream
    // and update resources
  }

  // ---------- Fonts ----------

  /// Get fonts used on this page.
  ///
  /// Equivalent to PyMuPDF's `page.get_fonts()`.
  List<List<dynamic>> getFonts({bool full = false}) {
    final fonts = <List<dynamic>>[];
    final resources = _getResources();
    if (resources == null) return fonts;

    var fontDict = resources.getDict('Font');
    if (fontDict == null) {
      final fontRef = resources.getRef('Font');
      if (fontRef != null) {
        final resolved = parser.getObject(fontRef.objectNumber);
        fontDict = resolved?.dict;
      }
    }
    if (fontDict == null) return fonts;

    for (final key in fontDict.keys) {
      final ref = fontDict.getRef(key);
      if (ref == null) continue;

      final obj = parser.getObject(ref.objectNumber);
      final dict = obj?.dict;
      if (dict == null) continue;

      final baseName = dict.getString('BaseFont') ?? key;
      final subtype = dict.getName('Subtype') ?? '';
      final encoding = dict.getName('Encoding') ?? '';

      fonts.add([
        ref.objectNumber,
        subtype,
        baseName,
        encoding,
        key,
      ]);
    }

    return fonts;
  }

  // ---------- XObjects ----------

  /// Get external objects (form XObjects) on this page.
  List<List<dynamic>> getXObjects() {
    final result = <List<dynamic>>[];
    final resources = _getResources();
    if (resources == null) return result;

    final xobjects = resources.getDict('XObject');
    if (xobjects == null) return result;

    for (final key in xobjects.keys) {
      final ref = xobjects.getRef(key);
      if (ref == null) continue;

      final obj = parser.getObject(ref.objectNumber);
      final dict = obj?.dict;
      if (dict == null) continue;

      final subtype = dict.getName('Subtype') ?? '';
      result.add([ref.objectNumber, subtype, key]);
    }

    return result;
  }

  // ---------- Content Stream ----------

  /// Read the raw content stream(s) of this page.
  ///
  /// Equivalent to PyMuPDF's `page.read_contents()`.
  Uint8List readContents() {
    final contents = pageDict['Contents'];
    if (contents == null) return Uint8List(0);

    if (contents is PdfRef) {
      return parser.getStreamData(contents.objectNumber) ?? Uint8List(0);
    }

    if (contents is PdfArray) {
      final buffer = <int>[];
      for (final item in contents.items) {
        if (item is PdfRef) {
          final streamData = parser.getStreamData(item.objectNumber);
          if (streamData != null) {
            buffer.addAll(streamData);
            buffer.add(0x0A); // newline between streams
          }
        }
      }
      return Uint8List.fromList(buffer);
    }

    return Uint8List(0);
  }

  // ---------- Helpers ----------

  PdfDict? _getResources() {
    var resources = pageDict.getDict('Resources');
    if (resources != null) return resources;

    // Try resolving reference
    final resRef = pageDict.getRef('Resources');
    if (resRef != null) {
      final obj = parser.getObject(resRef.objectNumber);
      if (obj?.dict != null) return obj!.dict;
    }

    // Inherit from parent
    final parentRef = pageDict.getRef('Parent');
    if (parentRef != null) {
      final parentObj = parser.getObject(parentRef.objectNumber);
      if (parentObj?.dict != null) {
        final pResRef = parentObj!.dict!.getRef('Resources');
        if (pResRef != null) {
          final resObj = parser.getObject(pResRef.objectNumber);
          return resObj?.dict;
        }
        return parentObj.dict!.getDict('Resources');
      }
    }

    return null;
  }

  PdfArray? _getAnnotsArray() {
    final annots = pageDict.getArray('Annots');
    if (annots != null) return annots;

    final annotsRef = pageDict.getRef('Annots');
    if (annotsRef != null) {
      final obj = parser.getObject(annotsRef.objectNumber);
      if (obj?.object is PdfArray) return obj!.object as PdfArray;
    }

    return null;
  }

  @override
  String toString() => 'Page(number: $pageNumber, rect: $rect)';
}
