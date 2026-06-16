import 'dart:io';
import 'dart:typed_data';

import 'core/pdf_objects.dart';
import 'core/pdf_parser.dart';
import 'core/pdf_writer.dart';
import 'models/metadata.dart';
import 'models/toc_entry.dart';
import 'models/image_info.dart';
import 'models/embedded_file.dart';
import 'models/page_label.dart';
import 'models/outline_item.dart';
import 'page.dart';

/// PDF Document class, equivalent to PyMuPDF's `fitz.Document`.
///
/// This is the primary class for working with PDF documents:
/// - Opening existing PDFs from file/bytes
/// - Accessing pages, metadata, TOC
/// - Extracting images and text
/// - Manipulating pages (insert, delete, rotate, copy, move)
/// - Merging PDFs
/// - Saving modified documents
///
/// ## Usage
/// ```dart
/// final doc = Document.openBytes(pdfBytes);
/// print('Pages: ${doc.pageCount}');
/// final page = doc.getPage(0);
/// final text = page.getText();
/// doc.close();
/// ```
class Document {
  /// The underlying PDF parser.
  PdfParser? _parser;

  /// Cached page object numbers.
  List<int>? _pageObjectNumbers;

  /// Modified objects tracker.
  final Map<int, PdfIndirectObject> _modifiedObjects = {};

  /// Whether this document has been closed.
  bool _isClosed = false;

  /// The raw bytes of the document.
  Uint8List? _rawData;

  /// Source file path (if opened from file).
  String? _filePath;

  /// Pages cache.
  final Map<int, Page> _pageCache = {};

  /// Next object number for new objects.
  int _nextNewObjNum = 0;

  // ---------- Constructors ----------

  /// Open a PDF from raw bytes.
  Document.openBytes(Uint8List bytes) {
    _rawData = bytes;
    _parser = PdfParser(bytes);
    _nextNewObjNum = _parser!.objectCount + 1;
  }

  /// Open a PDF from a file path.
  factory Document.openFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', path);
    }
    final bytes = file.readAsBytesSync();
    final doc = Document.openBytes(bytes);
    doc._filePath = path;
    return doc;
  }

  /// Create a new empty PDF document.
  factory Document.create({double width = 595, double height = 842}) {
    final bytes = PdfWriter.createEmptyPdf();
    return Document.openBytes(bytes);
  }

  // ---------- Properties ----------

  /// Number of pages.
  int get pageCount {
    _ensureOpen();
    if (_pageObjectNumbers != null) {
      return _pageObjectNumbers!.length;
    }
    return _parser!.pageCount;
  }

  /// PDF version string (e.g., "1.7").
  String get pdfVersion {
    _ensureOpen();
    return _parser!.pdfVersion;
  }

  /// Whether the document is encrypted.
  bool get isEncrypted {
    _ensureOpen();
    return _parser!.encryption != null;
  }

  /// Whether the document needs a password.
  bool get needsPass {
    _ensureOpen();
    return isEncrypted && !(_parser!.encryption?.isAuthenticated ?? false);
  }

  /// Whether the document is a PDF (always true for this library).
  bool get isPDF => true;

  /// Whether this document has been closed.
  bool get isClosed => _isClosed;

  /// Whether the document is linearized (fast web view).
  bool get isLinearized {
    _ensureOpen();
    return _parser!.isLinearized;
  }

  /// Whether the document has been modified.
  bool get isDirty => _modifiedObjects.isNotEmpty;

  /// File path this document was opened from.
  String? get name => _filePath;

  /// Total number of cross-reference entries.
  int get xrefLength {
    _ensureOpen();
    return _parser!.objectCount;
  }

  // ---------- Metadata ----------

  /// Get document metadata.
  PdfMetadata get metadata {
    _ensureOpen();
    final info = _parser!.info;
    return PdfMetadata(
      title: _getInfoString(info, 'Title'),
      author: _getInfoString(info, 'Author'),
      subject: _getInfoString(info, 'Subject'),
      keywords: _getInfoString(info, 'Keywords'),
      creator: _getInfoString(info, 'Creator'),
      producer: _getInfoString(info, 'Producer'),
      creationDate: _getInfoString(info, 'CreationDate'),
      modDate: _getInfoString(info, 'ModDate'),
      format: 'PDF ${_parser!.pdfVersion}',
      encryption:
          isEncrypted ? _parser!.encryption!.algorithm.toString() : null,
    );
  }

  /// Set document metadata.
  void setMetadata(PdfMetadata meta) {
    _ensureOpen();
    // Find or create info dict
    var infoRef = _parser!.trailer.getRef('Info');
    PdfDict infoDict;
    int infoObjNum;

    if (infoRef != null) {
      infoObjNum = infoRef.objectNumber;
      infoDict = _parser!.getObject(infoObjNum)?.dict ?? PdfDict();
    } else {
      infoObjNum = _nextNewObjNum++;
      infoDict = PdfDict();
    }

    if (meta.title != null) infoDict['Title'] = PdfString(meta.title!);
    if (meta.author != null) infoDict['Author'] = PdfString(meta.author!);
    if (meta.subject != null) infoDict['Subject'] = PdfString(meta.subject!);
    if (meta.keywords != null) {
      infoDict['Keywords'] = PdfString(meta.keywords!);
    }
    if (meta.creator != null) infoDict['Creator'] = PdfString(meta.creator!);
    if (meta.producer != null) {
      infoDict['Producer'] = PdfString(meta.producer!);
    }

    _modifiedObjects[infoObjNum] = PdfIndirectObject(infoObjNum, 0, infoDict);
  }

  String? _getInfoString(PdfDict? info, String key) {
    if (info == null) return null;
    final obj = info[key];
    if (obj is PdfString) return obj.decoded;
    return null;
  }

  // ---------- Page Access ----------

  /// Get a page by 0-based index. Equivalent to PyMuPDF's `doc[n]`.
  Page getPage(int pageNumber) {
    _ensureOpen();
    if (pageNumber < 0 || pageNumber >= pageCount) {
      throw RangeError('Page $pageNumber out of range (0..${pageCount - 1})');
    }

    if (_pageCache.containsKey(pageNumber)) {
      return _pageCache[pageNumber]!;
    }

    final pageObjNums = _getPageObjectNumbers();
    final objNum = pageObjNums[pageNumber];
    // Check modified objects first (for newly created pages), then parser
    PdfDict? pageDict;
    if (_modifiedObjects.containsKey(objNum)) {
      final modObj = _modifiedObjects[objNum]!;
      pageDict = modObj.dict;
    } else {
      pageDict = _parser!.getObject(objNum)?.dict;
    }
    if (pageDict == null) {
      throw StateError('Cannot load page $pageNumber');
    }

    final page = Page(
      document: this,
      pageNumber: pageNumber,
      pageDict: pageDict,
      objectNumber: objNum,
      parser: _parser!,
    );
    _pageCache[pageNumber] = page;
    return page;
  }

  /// Shorthand for getPage.
  Page operator [](int index) => getPage(index);

  /// Iterate over all pages.
  Iterable<Page> get pages sync* {
    for (int i = 0; i < pageCount; i++) {
      yield getPage(i);
    }
  }

  List<int> _getPageObjectNumbers() {
    _pageObjectNumbers ??= _parser!.getPageObjectNumbers();
    return _pageObjectNumbers!;
  }

  // ---------- Table of Contents ----------

  /// Get the table of contents (bookmarks/outline).
  ///
  /// Returns a list of [TocEntry] objects.
  /// Equivalent to PyMuPDF's `doc.get_toc()`.
  List<TocEntry> getToc({bool simple = true}) {
    _ensureOpen();
    final catalog = _parser!.catalog;
    if (catalog == null) return [];

    final outlinesRef = catalog.getRef('Outlines');
    if (outlinesRef == null) return [];

    final outlinesObj = _parser!.getObject(outlinesRef.objectNumber);
    final outlinesDict = outlinesObj?.dict;
    if (outlinesDict == null) return [];

    final toc = <TocEntry>[];
    _readOutlineItems(outlinesDict, 1, toc);
    return toc;
  }

  void _readOutlineItems(PdfDict parent, int level, List<TocEntry> toc) {
    var firstRef = parent.getRef('First');
    while (firstRef != null) {
      final obj = _parser!.getObject(firstRef.objectNumber);
      final dict = obj?.dict;
      if (dict == null) break;

      final title = dict.getString('Title') ?? '';
      int pageNum = 0;

      // Get destination
      final dest = dict['Dest'];
      if (dest is PdfArray && dest.length > 0) {
        final pageRef = dest[0];
        if (pageRef is PdfRef) {
          pageNum = getPageNumberForRef(pageRef) + 1;
        }
      }
      final action = dict.getDict('A');
      if (action != null && pageNum == 0) {
        final actionDest = action['D'];
        if (actionDest is PdfArray && actionDest.length > 0) {
          final pageRef = actionDest[0];
          if (pageRef is PdfRef) {
            pageNum = getPageNumberForRef(pageRef) + 1;
          }
        }
      }

      toc.add(TocEntry(level: level, title: title, pageNumber: pageNum));

      // Recurse into children
      if (dict.containsKey('First')) {
        _readOutlineItems(dict, level + 1, toc);
      }

      // Next sibling
      firstRef = dict.getRef('Next');
    }
  }

  /// Set the table of contents.
  void setToc(List<TocEntry> toc) {
    _ensureOpen();
    // Build outline tree from flat list
    // This is a simplified implementation
    final catalog = _parser!.catalog;
    if (catalog == null) return;

    // For now, mark document as modified
    // Full implementation would build the outline tree
  }

  int getPageNumberForRef(PdfRef ref) {
    final pageNums = _getPageObjectNumbers();
    return pageNums.indexOf(ref.objectNumber);
  }

  // ---------- Image Extraction ----------

  /// Extract an image by its xref number.
  ///
  /// Equivalent to PyMuPDF's `doc.extract_image(xref)`.
  ExtractedImage? extractImage(int xref) {
    _ensureOpen();
    final obj = _parser!.getObject(xref);
    if (obj == null || !obj.isStream) return null;

    final stream = obj.object as PdfStream;
    final dict = stream.dict;

    final width = dict.getInt('Width') ?? 0;
    final height = dict.getInt('Height') ?? 0;
    final bpc = dict.getInt('BitsPerComponent') ?? 8;
    final csName = _getColorspaceName(dict);
    final cs = _colorspaceComponents(csName);

    // Determine image format from filter.
    //
    // getStreamData() applies the FULL filter chain. The image codecs
    // (DCT/JPX/CCITT/JBIG2) are pass-throughs in the decode pipeline, so for a
    // chain like [FlateDecode, DCTDecode] the FlateDecode is correctly removed
    // and we are left with the encoded JPEG bytes. Using stream.data here was a
    // bug: it returned the still-Flate-compressed bytes for such images.
    final filters = stream.filters;
    final decoded = _parser!.getStreamData(xref) ?? stream.data;
    final Uint8List imageData = decoded;
    String ext = 'png';

    if (filters.contains('DCTDecode')) {
      ext = 'jpeg';
    } else if (filters.contains('JPXDecode')) {
      ext = 'jp2';
    } else if (filters.contains('CCITTFaxDecode')) {
      ext = 'tiff';
    } else if (filters.contains('JBIG2Decode')) {
      ext = 'jbig2';
    } else {
      // Raw, fully-decompressed samples (not yet wrapped as a PNG file).
      ext = 'png';
    }

    // Handle soft mask (alpha channel)
    final smaskRef = dict.getRef('SMask');
    if (smaskRef != null) {
      // We note it but keep the main image
    }

    return ExtractedImage(
      xref: xref,
      ext: ext,
      colorspace: cs,
      width: width,
      height: height,
      bpc: bpc,
      image: imageData,
    );
  }

  String _getColorspaceName(PdfDict dict) {
    final cs = dict['ColorSpace'];
    if (cs is PdfName) return cs.value;
    if (cs is PdfRef) {
      final resolved = _parser!.resolve(cs);
      if (resolved is PdfName) return resolved.value;
      if (resolved is PdfArray && resolved.length > 0) {
        final first = resolved[0];
        if (first is PdfName) return first.value;
      }
    }
    if (cs is PdfArray && cs.length > 0) {
      final first = cs[0];
      if (first is PdfName) return first.value;
    }
    return 'DeviceRGB';
  }

  int _colorspaceComponents(String name) {
    switch (name) {
      case 'DeviceGray':
      case 'CalGray':
      case 'G':
        return 1;
      case 'DeviceRGB':
      case 'CalRGB':
      case 'RGB':
        return 3;
      case 'DeviceCMYK':
      case 'CMYK':
        return 4;
      case 'ICCBased':
        return 3; // Usually
      default:
        return 3;
    }
  }

  // ---------- Embedded Files ----------

  /// Get list of embedded file names.
  List<String> get embeddedFileNames {
    _ensureOpen();
    final names = <String>[];
    final catalog = _parser!.catalog;
    if (catalog == null) return names;

    final namesDict = _resolveDict(catalog.getRef('Names'));
    if (namesDict == null) return names;

    final efTree = _resolveDict(namesDict.getRef('EmbeddedFiles'));
    if (efTree == null) return names;

    _collectNameTreeEntries(efTree, names);
    return names;
  }

  /// Get an embedded file by name.
  EmbeddedFile? getEmbeddedFile(String name) {
    _ensureOpen();
    // Search the names tree for the entry
    final catalog = _parser!.catalog;
    if (catalog == null) return null;

    final namesDict = _resolveDict(catalog.getRef('Names'));
    if (namesDict == null) return null;

    final efTree = _resolveDict(namesDict.getRef('EmbeddedFiles'));
    if (efTree == null) return null;

    final fileSpec = _findInNameTree(efTree, name);
    if (fileSpec == null) return null;

    final ef = fileSpec.getDict('EF');
    if (ef == null) return null;

    final fRef = ef.getRef('F');
    if (fRef == null) return null;

    final streamData = _parser!.getStreamData(fRef.objectNumber);
    if (streamData == null) return null;

    return EmbeddedFile(
      name: name,
      filename: fileSpec.getString('F'),
      ufilename: fileSpec.getString('UF'),
      description: fileSpec.getString('Desc'),
      content: streamData,
      size: streamData.length,
    );
  }

  /// Number of embedded files.
  int get embeddedFileCount => embeddedFileNames.length;

  // ---------- Page Manipulation ----------

  /// Create a new blank page.
  ///
  /// Equivalent to PyMuPDF's `doc.new_page()`.
  Page newPage({
    int? index,
    double width = 595,
    double height = 842,
  }) {
    _ensureOpen();
    // Create a new page object
    final insertAt = index ?? pageCount;

    // Create content stream
    final contentObjNum = _nextNewObjNum++;
    final contentStream = PdfStream(PdfDict(), Uint8List(0));
    _modifiedObjects[contentObjNum] =
        PdfIndirectObject(contentObjNum, 0, contentStream);

    // Create page dict
    final pageObjNum = _nextNewObjNum++;
    final pageDict = PdfDict({
      'Type': PdfName('/Page'),
      'MediaBox': PdfArray([
        PdfInt(0),
        PdfInt(0),
        PdfReal(width),
        PdfReal(height),
      ]),
      'Contents': PdfRef(contentObjNum),
      'Resources': PdfDict(),
    });

    // Set parent
    final pagesRef = _parser!.catalog?.getRef('Pages');
    if (pagesRef != null) {
      pageDict['Parent'] = pagesRef;
    }

    _modifiedObjects[pageObjNum] = PdfIndirectObject(pageObjNum, 0, pageDict);

    // Update page list
    _pageObjectNumbers ??= _parser!.getPageObjectNumbers();
    if (insertAt >= _pageObjectNumbers!.length) {
      _pageObjectNumbers!.add(pageObjNum);
    } else {
      _pageObjectNumbers!.insert(insertAt, pageObjNum);
    }

    // Clear page cache
    _pageCache.clear();

    return getPage(insertAt);
  }

  /// Delete a page by 0-based index.
  ///
  /// Equivalent to PyMuPDF's `doc.delete_page()`.
  void deletePage(int pageNumber) {
    _ensureOpen();
    if (pageNumber < 0 || pageNumber >= pageCount) {
      throw RangeError('Page $pageNumber out of range');
    }

    _pageObjectNumbers ??= _parser!.getPageObjectNumbers();
    _pageObjectNumbers!.removeAt(pageNumber);
    _pageCache.remove(pageNumber);
    // Re-index cached pages
    final newCache = <int, Page>{};
    _pageCache.forEach((key, value) {
      if (key > pageNumber) {
        newCache[key - 1] = value;
      } else {
        newCache[key] = value;
      }
    });
    _pageCache
      ..clear()
      ..addAll(newCache);
  }

  /// Delete pages by range.
  void deletePages({required int from, required int to}) {
    for (int i = to; i >= from; i--) {
      deletePage(i);
    }
  }

  /// Copy a page within the document.
  void copyPage(int pageNumber, {int? to}) {
    _ensureOpen();
    if (pageNumber < 0 || pageNumber >= pageCount) {
      throw RangeError('Page $pageNumber out of range');
    }

    _pageObjectNumbers ??= _parser!.getPageObjectNumbers();
    final srcObjNum = _pageObjectNumbers![pageNumber];
    final insertAt = to ?? _pageObjectNumbers!.length;

    // Create a copy reference (in a full implementation, deep-copy the page tree)
    _pageObjectNumbers!.insert(insertAt, srcObjNum);
    _pageCache.clear();
  }

  /// Move a page to a new position.
  void movePage({required int from, required int to}) {
    _ensureOpen();
    _pageObjectNumbers ??= _parser!.getPageObjectNumbers();

    if (from < 0 || from >= _pageObjectNumbers!.length) {
      throw RangeError('Source page $from out of range');
    }

    final objNum = _pageObjectNumbers!.removeAt(from);
    final insertAt = to > from ? to - 1 : to;
    _pageObjectNumbers!
        .insert(insertAt.clamp(0, _pageObjectNumbers!.length), objNum);
    _pageCache.clear();
  }

  /// Select specific pages (discard all others).
  ///
  /// Equivalent to PyMuPDF's `doc.select()`.
  void select(List<int> pages) {
    _ensureOpen();
    _pageObjectNumbers ??= _parser!.getPageObjectNumbers();

    final newList = <int>[];
    for (final idx in pages) {
      if (idx >= 0 && idx < _pageObjectNumbers!.length) {
        newList.add(_pageObjectNumbers![idx]);
      }
    }
    _pageObjectNumbers = newList;
    _pageCache.clear();
  }

  /// Insert pages from another PDF document.
  ///
  /// Equivalent to PyMuPDF's `doc.insert_pdf()`.
  void insertPdf(
    Document source, {
    int fromPage = 0,
    int? toPage,
    int? startAt,
    List<int>? rotate,
    bool links = true,
    bool annots = true,
  }) {
    _ensureOpen();
    source._ensureOpen();

    final endPage = toPage ?? source.pageCount - 1;
    final insertAt = startAt ?? pageCount;

    _pageObjectNumbers ??= _parser!.getPageObjectNumbers();

    // For each page in source, we need to copy the objects
    // This is a simplified implementation
    for (int i = fromPage; i <= endPage; i++) {
      // Create a new page referencing the source content
      final srcPage = source.getPage(i);
      final newPageNum = _nextNewObjNum++;

      final pageDict = PdfDict({
        'Type': PdfName('/Page'),
        'MediaBox': PdfArray([
          PdfReal(srcPage.rect.x0),
          PdfReal(srcPage.rect.y0),
          PdfReal(srcPage.rect.x1),
          PdfReal(srcPage.rect.y1),
        ]),
        'Resources': PdfDict(),
      });

      _modifiedObjects[newPageNum] = PdfIndirectObject(newPageNum, 0, pageDict);
      _pageObjectNumbers!.insert(
        (insertAt + (i - fromPage)).clamp(0, _pageObjectNumbers!.length),
        newPageNum,
      );
    }

    _pageCache.clear();
  }

  // ---------- Authentication ----------

  /// Authenticate with a password.
  ///
  /// Returns true if authentication succeeded.
  bool authenticate(String password) {
    _ensureOpen();
    if (_parser!.encryption == null) return true;
    return _parser!.encryption!.authenticate(password);
  }

  /// Whether authentication has been completed.
  bool get isAuthenticated {
    if (_parser!.encryption == null) return true;
    return _parser!.encryption!.isAuthenticated;
  }

  // ---------- Save & Export ----------

  /// Save the document to bytes.
  ///
  /// Equivalent to PyMuPDF's `doc.tobytes()`.
  Uint8List toBytes({
    int garbage = 0,
    bool deflate = true,
    bool clean = false,
    bool incremental = false,
    bool linearize = false,
  }) {
    _ensureOpen();

    if (!isDirty && _pageObjectNumbers == null && _rawData != null) {
      return _rawData!;
    }

    // Update the Pages tree if pages have been modified
    _updatePagesTree();

    // Rebuild the PDF
    final writer = PdfWriter();

    // Collect the set of object numbers that are modified
    final modifiedObjNums = _modifiedObjects.keys.toSet();

    // Copy existing objects preserving their original object numbers
    for (final objNum in _parser!.crossRef.liveObjectNumbers) {
      if (modifiedObjNums.contains(objNum)) continue;
      final obj = _parser!.getObject(objNum);
      if (obj != null) {
        writer.addObjectWithNum(objNum, obj.generation, obj.object);
      }
    }

    // Add modified/new objects with their assigned object numbers
    for (final entry in _modifiedObjects.entries) {
      writer.addObjectWithNum(
          entry.key, entry.value.generation, entry.value.object);
    }

    // Set trailer
    final rootRef = _parser!.trailer.getRef('Root') ?? PdfRef(1);
    final trailerDict = PdfDict({
      'Root': rootRef,
    });

    final info = _parser!.trailer.getRef('Info');
    if (info != null) {
      trailerDict['Info'] = info;
    }

    // Preserve document ID if present
    final idArray = _parser!.trailer.getArray('ID');
    if (idArray != null) {
      trailerDict['ID'] = idArray;
    }

    writer.setTrailer(trailerDict);

    return writer.write(garbage: garbage, deflate: deflate);
  }

  /// Update the Pages tree to reflect current page list.
  void _updatePagesTree() {
    if (_pageObjectNumbers == null) return;

    final catalog = _parser!.catalog;
    if (catalog == null) return;

    final pagesRef = catalog.getRef('Pages');
    if (pagesRef == null) return;

    // Build updated Kids array and Count
    final kids = PdfArray(
      _pageObjectNumbers!.map((n) => PdfRef(n)).toList(),
    );

    // Get or create the Pages dict
    PdfDict pagesDict;
    if (_modifiedObjects.containsKey(pagesRef.objectNumber)) {
      pagesDict = _modifiedObjects[pagesRef.objectNumber]!.dict ?? PdfDict();
    } else {
      final pagesObj = _parser!.getObject(pagesRef.objectNumber);
      pagesDict =
          PdfDict(Map<String, PdfObject>.from(pagesObj?.dict?.map ?? {}));
    }

    pagesDict['Kids'] = kids;
    pagesDict['Count'] = PdfInt(_pageObjectNumbers!.length);
    pagesDict['Type'] = PdfName('/Pages');

    _modifiedObjects[pagesRef.objectNumber] =
        PdfIndirectObject(pagesRef.objectNumber, 0, pagesDict);
  }

  /// Save to a file.
  ///
  /// Equivalent to PyMuPDF's `doc.save()`.
  void save(
    String filename, {
    int garbage = 0,
    bool deflate = true,
    bool clean = false,
    bool incremental = false,
  }) {
    final bytes = toBytes(
      garbage: garbage,
      deflate: deflate,
      clean: clean,
      incremental: incremental,
    );
    File(filename).writeAsBytesSync(bytes);
  }

  /// Save incrementally (append changes to the original file).
  void saveIncr() {
    if (_filePath != null) {
      save(_filePath!, incremental: true);
    }
  }

  // ---------- XRef Access ----------

  /// Get the PDF object string for a given xref number.
  ///
  /// Equivalent to PyMuPDF's `doc.xref_object()`.
  String xrefObject(int xref) {
    _ensureOpen();
    final obj = _parser!.getObject(xref);
    if (obj == null) return '';
    return obj.object.toPdfString();
  }

  /// Get a key's value from an xref dictionary.
  (String, String) xrefGetKey(int xref, String key) {
    _ensureOpen();
    final obj = _parser!.getObject(xref);
    final dict = obj?.dict;
    if (dict == null) return ('null', 'null');

    final value = dict[key];
    if (value == null) return ('null', 'null');

    if (value is PdfName) return ('name', value.toPdfString());
    if (value is PdfString) return ('string', value.decoded);
    if (value is PdfInt) return ('int', value.value.toString());
    if (value is PdfReal) return ('real', value.value.toString());
    if (value is PdfBool) return ('bool', value.value.toString());
    if (value is PdfRef) return ('xref', value.toPdfString());
    if (value is PdfArray) return ('array', value.toPdfString());
    if (value is PdfDict) return ('dict', value.toPdfString());
    return ('unknown', value.toPdfString());
  }

  /// Get all keys of an xref dictionary.
  List<String> xrefGetKeys(int xref) {
    _ensureOpen();
    final obj = _parser!.getObject(xref);
    final dict = obj?.dict;
    if (dict == null) return [];
    return dict.keys.toList();
  }

  /// Whether an xref is a stream.
  bool xrefIsStream(int xref) {
    _ensureOpen();
    final obj = _parser!.getObject(xref);
    return obj?.isStream ?? false;
  }

  /// Whether an xref is an image.
  bool xrefIsImage(int xref) {
    _ensureOpen();
    final obj = _parser!.getObject(xref);
    final dict = obj?.dict;
    if (dict == null) return false;
    return dict.getName('Subtype') == 'Image';
  }

  /// Whether an xref is a font.
  bool xrefIsFont(int xref) {
    _ensureOpen();
    final obj = _parser!.getObject(xref);
    final dict = obj?.dict;
    if (dict == null) return false;
    return dict.getName('Type') == 'Font';
  }

  /// Get stream data for an xref.
  Uint8List? xrefStream(int xref) {
    _ensureOpen();
    return _parser!.getStreamData(xref);
  }

  // ---------- Page Labels ----------

  /// Get page labels.
  List<PageLabel> getPageLabels() {
    _ensureOpen();
    final catalog = _parser!.catalog;
    if (catalog == null) return [];

    final labelsObj = catalog['PageLabels'];
    if (labelsObj == null) return [];

    // Parse the number tree
    // Simplified implementation
    return [];
  }

  // ---------- Outline (alternative to TOC) ----------

  /// Get the document outline.
  OutlineItem? get outline {
    final toc = getToc();
    if (toc.isEmpty) return null;

    // Build tree from flat list
    final root = OutlineItem(title: '', page: -1, children: []);
    final stack = <List<OutlineItem>>[root.children];

    for (final entry in toc) {
      while (stack.length > entry.level) {
        stack.removeLast();
      }
      while (stack.length < entry.level) {
        final last = stack.last.isNotEmpty ? stack.last.last : root;
        stack.add(last.children);
      }

      final item = OutlineItem(
        title: entry.title,
        page: entry.pageNumber - 1,
        level: entry.level,
      );
      stack.last.add(item);
    }

    return root.children.isNotEmpty ? root.children.first : null;
  }

  // ---------- Utilities ----------

  /// Close the document and free resources.
  void close() {
    _isClosed = true;
    _parser = null;
    _rawData = null;
    _pageCache.clear();
    _modifiedObjects.clear();
    _pageObjectNumbers = null;
  }

  void _ensureOpen() {
    if (_isClosed) throw StateError('Document has been closed');
    if (_parser == null) throw StateError('Document not initialized');
  }

  PdfDict? _resolveDict(PdfRef? ref) {
    if (ref == null) return null;
    final obj = _parser!.getObject(ref.objectNumber);
    return obj?.dict;
  }

  void _collectNameTreeEntries(PdfDict node, List<String> names) {
    final namesArray = node.getArray('Names');
    if (namesArray != null) {
      for (int i = 0; i < namesArray.length - 1; i += 2) {
        final key = namesArray[i];
        if (key is PdfString) names.add(key.decoded);
      }
    }

    final kids = node.getArray('Kids');
    if (kids != null) {
      for (final kid in kids.items) {
        if (kid is PdfRef) {
          final childDict = _resolveDict(kid);
          if (childDict != null) {
            _collectNameTreeEntries(childDict, names);
          }
        }
      }
    }
  }

  PdfDict? _findInNameTree(PdfDict node, String name) {
    final namesArray = node.getArray('Names');
    if (namesArray != null) {
      for (int i = 0; i < namesArray.length - 1; i += 2) {
        final key = namesArray[i];
        if (key is PdfString && key.decoded == name) {
          final val = namesArray[i + 1];
          if (val is PdfRef) {
            return _parser!.getObject(val.objectNumber)?.dict;
          }
          if (val is PdfDict) return val;
        }
      }
    }

    final kids = node.getArray('Kids');
    if (kids != null) {
      for (final kid in kids.items) {
        if (kid is PdfRef) {
          final childDict = _resolveDict(kid);
          if (childDict != null) {
            final result = _findInNameTree(childDict, name);
            if (result != null) return result;
          }
        }
      }
    }

    return null;
  }

  @override
  String toString() {
    if (_isClosed) return 'Document(closed)';
    return 'Document(pages: $pageCount, version: $pdfVersion)';
  }
}
