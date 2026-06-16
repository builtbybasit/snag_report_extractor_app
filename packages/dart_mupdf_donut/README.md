# dart_mupdf_donut

A comprehensive **pure Dart** PDF library **+** OCR-free Document Understanding Transformer ([Donut](https://arxiv.org/abs/2111.15664)).  
No native dependencies — works on **all platforms** (Android, iOS, Web, macOS, Windows, Linux).

[![pub package](https://img.shields.io/pub/v/dart_mupdf_donut.svg)](https://pub.dev/packages/dart_mupdf_donut)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub](https://img.shields.io/github/stars/proethiopia/dart-mupdf-donut?style=social)](https://github.com/proethiopia/dart-mupdf-donut)

---

## What's Inside

| Module | Description |
|--------|-------------|
| **dart_mupdf** | Pure Dart PDF engine inspired by [PyMuPDF](https://github.com/pymupdf/PyMuPDF) — parse, extract text/images, annotate, merge, create PDFs |
| **donut** | Pure Dart [Donut](https://github.com/clovaai/donut) implementation — Swin Transformer encoder + mBART decoder for structured document extraction from images (receipts, invoices, forms) |

---

## Table of Contents

- [dart\_mupdf\_donut](#dart_mupdf_donut)
  - [What's Inside](#whats-inside)
  - [Table of Contents](#table-of-contents)
  - [Installation](#installation)
  - [PDF Module — Quick Start](#pdf-module--quick-start)
  - [PDF Features](#pdf-features)
  - [PDF Advanced Usage](#pdf-advanced-usage)
    - [Text Extraction Modes](#text-extraction-modes)
    - [Page Manipulation](#page-manipulation)
    - [Annotations](#annotations)
    - [Drawing with Shape](#drawing-with-shape)
  - [Donut Module — Quick Start](#donut-module--quick-start)
    - [Combine with PDF Pages](#combine-with-pdf-pages)
  - [Donut Architecture](#donut-architecture)
  - [Donut Supported Tasks](#donut-supported-tasks)
  - [Donut Configuration](#donut-configuration)
  - [Donut Image Preprocessing](#donut-image-preprocessing)
  - [Donut JSON ↔ Token Conversion](#donut-json--token-conversion)
  - [Tensor Operations](#tensor-operations)
  - [Neural Network Layers](#neural-network-layers)
  - [Exporting Weights from Python](#exporting-weights-from-python)
    - [Safetensors (recommended)](#safetensors-recommended)
    - [JSON (portable)](#json-portable)
  - [API Reference](#api-reference)
    - [PDF Core](#pdf-core)
    - [Donut Core](#donut-core)
    - [Donut Encoder / Decoder](#donut-encoder--decoder)
    - [Tensor \& NN](#tensor--nn)
    - [Geometry](#geometry)
    - [Compatible Pretrained Models](#compatible-pretrained-models)
  - [Platform Support](#platform-support)
  - [License](#license)
  - [References](#references)

---

## Installation

```yaml
dependencies:
  dart_mupdf_donut: ^1.0.0
```

```bash
dart pub get
```

---

## PDF Module — Quick Start

```dart
import 'package:dart_mupdf_donut/dart_mupdf.dart';

// Open a PDF
final doc = DartMuPDF.openBytes(pdfBytes);
print('Pages: ${doc.pageCount}');
print('Title: ${doc.metadata.title}');

// Extract text
final page = doc.getPage(0);
print(page.getText());

// Search
for (final rect in page.searchFor('invoice')) {
  print('Found at: $rect');
}

// Extract images
for (final img in page.getImages()) {
  final data = doc.extractImage(img.xref);
  print('Image: ${data.width}x${data.height}');
}

// Table of contents
for (final entry in doc.getToc()) {
  print('${"  " * (entry.level - 1)}${entry.title} → p.${entry.pageNumber}');
}

doc.close();
```

---

## PDF Features

| Feature | PyMuPDF (Python) | dart_mupdf_donut (Dart) |
|---------|------------------|-------------------------|
| Open PDF from file/bytes | ✅ `fitz.open()` | ✅ `DartMuPDF.openFile()` / `openBytes()` |
| Page count & metadata | ✅ `doc.page_count` | ✅ `doc.pageCount` / `doc.metadata` |
| Extract plain text | ✅ `page.get_text()` | ✅ `page.getText()` |
| Extract text blocks | ✅ `page.get_text("blocks")` | ✅ `page.getTextBlocks()` |
| Extract text words | ✅ `page.get_text("words")` | ✅ `page.getTextWords()` |
| Extract text as dict | ✅ `page.get_text("dict")` | ✅ `page.getTextDict()` |
| Search text | ✅ `page.search_for()` | ✅ `page.searchFor()` |
| Get images list | ✅ `page.get_images()` | ✅ `page.getImages()` |
| Extract image bytes | ✅ `doc.extract_image()` | ✅ `doc.extractImage()` |
| Get links | ✅ `page.get_links()` | ✅ `page.getLinks()` |
| Table of contents | ✅ `doc.get_toc()` | ✅ `doc.getToc()` |
| Annotations | ✅ `page.annots()` | ✅ `page.getAnnotations()` |
| Insert text | ✅ `page.insert_text()` | ✅ `page.insertText()` |
| Insert image | ✅ `page.insert_image()` | ✅ `page.insertImage()` |
| Merge PDFs | ✅ `doc.insert_pdf()` | ✅ `doc.insertPdf()` |
| Delete / rotate / copy pages | ✅ | ✅ |
| Create new PDF | ✅ `fitz.open()` | ✅ `DartMuPDF.createPdf()` |
| Save to bytes / file | ✅ `doc.tobytes()` | ✅ `doc.toBytes()` / `doc.save()` |
| Encryption & auth | ✅ | ✅ `doc.isEncrypted` / `doc.authenticate()` |
| Embedded files | ✅ `doc.embfile_*` | ✅ `doc.embeddedFiles` |
| Form fields | ✅ `page.widgets()` | ✅ `page.getWidgets()` |
| Page labels | ✅ | ✅ `doc.getPageLabels()` |
| PDF repair | ✅ `garbage=3` | ✅ `doc.save(garbage: 3)` |

---

## PDF Advanced Usage

### Text Extraction Modes

```dart
final text   = page.getText();           // plain text
final blocks = page.getTextBlocks();     // blocks with position
final words  = page.getTextWords();      // individual words
final dict   = page.getTextDict();       // full structure
final html   = page.getText(format: TextFormat.html);
```

### Page Manipulation

```dart
doc.deletePage(2);
doc.getPage(0).setRotation(90);
doc.movePage(from: 5, to: 0);
doc.select([0, 2, 4]);
doc.copyPage(0, to: doc.pageCount);
```

### Annotations

```dart
for (final a in page.getAnnotations()) {
  print('${a.type}: ${a.content}');
}
page.addHighlightAnnot(quads);
page.addTextAnnot(Point(100, 100), 'Note');
```

### Drawing with Shape

```dart
final shape = Shape(pageWidth: 595, pageHeight: 842);
shape.drawRect(Rect(50, 50, 300, 200));
shape.finish(color: [1, 0, 0], fill: [0.9, 0.9, 1.0], width: 1);
shape.drawCircle(Point(200, 400), 50);
shape.finish(color: [0, 0, 1], width: 1.5);
final stream = shape.commit();
```

---

## Donut Module — Quick Start

```dart
import 'package:dart_mupdf_donut/donut.dart';
import 'dart:io';

// 1. Configure & build model
final config = DonutConfig.base();
final model  = DonutModel(config);

// 2. Load pretrained weights (from HuggingFace export)
await model.loadWeights('path/to/donut-model/');
model.loadTokenizerFromFile('path/to/tokenizer.json');

// 3. Run inference on a receipt image
final bytes  = File('receipt.jpg').readAsBytesSync();
final result = model.inferenceFromBytes(
  imageBytes: bytes,
  prompt: '<s_cord-v2>',
);

// 4. Structured JSON output
print(result.json);
// {
//   "menu": [
//     {"nm": "Cappuccino", "price": "4.50"},
//     {"nm": "Croissant",  "price": "3.00"}
//   ],
//   "total": {"total_price": "7.50"}
// }
```

### Combine with PDF Pages

```dart
import 'package:dart_mupdf_donut/dart_mupdf.dart';
import 'package:dart_mupdf_donut/donut.dart';

final doc  = DartMuPDF.openBytes(pdfBytes);
final page = doc.getPage(0);
final png  = page.getPixmap(dpi: 150).toPng();

final model = DonutModel(DonutConfig.base());
await model.loadWeights('model/');
model.loadTokenizerFromFile('tokenizer.json');

final result = model.inferenceFromBytes(
  imageBytes: png,
  prompt: '<s_cord-v2>',
);
print(result.json);
doc.close();
```

---

## Donut Architecture

```
Document Image
      │
      ▼
┌─────────────────────────┐
│     Swin Encoder         │  Hierarchical vision transformer
│  Patch Embed → Stages    │  Window attention + patch merging
│  [2, 2, 14, 2] layers   │  Output: (1, N, 1024) features
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│     BART Decoder         │  Auto-regressive text decoder
│  Cross-attention to      │  4 layers × 16 heads
│  encoder features        │  Generates structured tokens
└───────────┬─────────────┘
            │
            ▼
    Structured JSON Output
```

**Key insight**: Donut skips OCR entirely — it learns to read documents end-to-end from pixels to structured data.

---

## Donut Supported Tasks

| Task | Prompt | Output |
|------|--------|--------|
| **Receipt Parsing** (CORD-v2) | `<s_cord-v2>` | Menu items, prices, totals |
| **Document Classification** (RVL-CDIP) | `<s_rvlcdip>` | `"letter"`, `"invoice"`, etc. |
| **Visual QA** (DocVQA) | `<s_docvqa><s_question>…</s_question><s_answer>` | Free-text answer |
| **Text Reading** (SynthDoG) | `<s_synthdog>` | OCR-free text |

---

## Donut Configuration

```dart
// Default (matches HuggingFace donut-base)
final config = DonutConfig.base();

// Custom
final config = DonutConfig(
  inputSize: [1280, 960],
  windowSize: 10,
  encoderLayer: [2, 2, 14, 2],
  decoderLayer: 4,
  maxLength: 1536,
  encoderEmbedDim: 128,
  encoderNumHeads: [4, 8, 16, 32],
  decoderEmbedDim: 1024,
  decoderFfnDim: 4096,
  decoderNumHeads: 16,
  vocabSize: 57522,
);

// Small (for testing / dev)
final config = DonutConfig.small();

// From HuggingFace config.json
final config = DonutConfig.fromJson(jsonDecode(str));
```

---

## Donut Image Preprocessing

```dart
// From file bytes (PNG, JPEG, etc.)
final tensor = DonutImageUtils.preprocessBytes(imageBytes, config);
// → Tensor shape [1, 3, H, W] with ImageNet normalization

// Pipeline description
print(DonutImageUtils.describePipeline(config));
// 1. Decode → RGB
// 2. Resize to fit [H, W] (aspect ratio preserved)
// 3. Pad with white
// 4. Normalize: (px/255 − μ) / σ   (ImageNet stats)
// 5. → Tensor [1, 3, H, W]

// Debug: tensor back to image
final debugImg = DonutImageUtils.tensorToImage(tensor);
```

---

## Donut JSON ↔ Token Conversion

Donut uses XML-like tokens for structured output:

```dart
// JSON → Donut tokens
final tokens = DonutModel.json2token({
  'menu': [
    {'nm': 'Latte',  'price': '5.0'},
    {'nm': 'Muffin', 'price': '3.5'},
  ],
  'total': {'total_price': '8.5'},
});
// → '<s_menu><s_nm>Latte</s_nm><s_price>5.0</s_price><sep/>
//    <s_nm>Muffin</s_nm><s_price>3.5</s_price></s_menu>
//    <s_total><s_total_price>8.5</s_total_price></s_total>'

// Donut tokens → JSON
final json = DonutModel.token2json(tokens);
// → {'menu': [...], 'total': {'total_price': '8.5'}}
```

---

## Tensor Operations

```dart
import 'package:dart_mupdf_donut/donut.dart';

final a = Tensor.zeros([2, 3]);
final b = Tensor.ones([2, 3]);
final c = a + b;                 // element-wise add
final d = c * Tensor.full([2, 3], 2.0);

// Matrix multiply
final y = Tensor.ones([2, 4]).matmul(Tensor.ones([4, 3]));

// Reshape, permute, transpose
final r = y.reshape([1, 2, 3]);
final p = r.permute([0, 2, 1]);

// Reductions
final s = y.sum(1);
final m = y.mean(0);

// Activations
final g = y.gelu();
final sm = y.softmax(1);
```

---

## Neural Network Layers

```dart
final linear = Linear(512, 256);
final output = linear.forward(input);

final norm = LayerNorm(256);
final normalized = norm.forward(output);

final embed = Embedding(50000, 1024);
final embedded = embed.forward([1, 42, 100]);

final attn = MultiHeadAttention(embedDim: 1024, numHeads: 16);
final attended = attn.forward(query, key, value);

final conv = Conv2d(3, 64, 4, stride: 4);
final features = conv.forward(imageTensor);
```

---

## Exporting Weights from Python

### Safetensors (recommended)

```bash
pip install huggingface_hub
python -c "
from huggingface_hub import snapshot_download
snapshot_download('naver-clova-ix/donut-base-finetuned-cord-v2',
                  local_dir='./donut-cord-v2/')
"
```

### JSON (portable)

```python
import torch, json, base64
from transformers import VisionEncoderDecoderModel

model = VisionEncoderDecoderModel.from_pretrained(
    "naver-clova-ix/donut-base-finetuned-cord-v2"
)

weights = {}
for name, param in model.named_parameters():
    t = param.detach().cpu().float().numpy()
    weights[name] = {
        "shape": list(t.shape),
        "dtype": "float32",
        "data": base64.b64encode(t.tobytes()).decode("ascii"),
    }

with open("weights.json", "w") as f:
    json.dump(weights, f)
```

---

## API Reference

### PDF Core

| Class | Description |
|-------|-------------|
| `DartMuPDF` | Entry point — `openFile()`, `openBytes()`, `createPdf()` |
| `Document` | PDF document — pages, metadata, TOC, merge, save |
| `Page` | Single page — text, images, links, annotations, render |
| `Pixmap` | Pixel buffer — convert, export PNG |
| `Shape` | Drawing API — lines, rects, circles, text |
| `TextPage` | Parsed text layer — blocks, words, search |

### Donut Core

| Class | Description |
|-------|-------------|
| `DonutModel` | Main model — encoder + decoder + inference |
| `DonutConfig` | All hyperparameters (input size, layers, dims) |
| `DonutResult` | Output — `.tokens`, `.text`, `.json` |
| `DonutTokenizer` | SentencePiece BPE tokenizer |
| `DonutImageUtils` | Resize, normalize, pad images |
| `DonutWeightLoader` | Load safetensors / JSON weights |

### Donut Encoder / Decoder

| Class | Description |
|-------|-------------|
| `SwinEncoder` | Swin Transformer visual encoder |
| `BartDecoder` | mBART auto-regressive decoder |
| `SwinTransformerBlock` | Window attention block |
| `BartDecoderLayer` | Self-attn → cross-attn → FFN |
| `WindowAttention` | Shifted window attention |
| `PatchEmbed` | Conv2d patch embedding |
| `PatchMerging` | 2× spatial downsample |

### Tensor & NN

| Class | Description |
|-------|-------------|
| `Tensor` | N-dim array — matmul, softmax, GELU, broadcasting |
| `Linear` | y = xW^T + b |
| `LayerNorm` | Layer normalization |
| `Embedding` | Token / position lookup |
| `Conv2d` | 2D convolution |
| `MultiHeadAttention` | Scaled dot-product attention |
| `FeedForward` | 2-layer MLP + GELU |

### Geometry

| Class | Description |
|-------|-------------|
| `Point` | 2D point |
| `Rect` | Bounding rectangle |
| `IRect` | Integer rectangle |
| `Matrix` | 3×3 transformation matrix |
| `Quad` | Quadrilateral (4 points) |

### Compatible Pretrained Models

| Model | Task | HuggingFace ID |
|-------|------|----------------|
| Donut Base | General | `naver-clova-ix/donut-base` |
| CORD v2 | Receipt parsing | `naver-clova-ix/donut-base-finetuned-cord-v2` |
| RVL-CDIP | Doc classification | `naver-clova-ix/donut-base-finetuned-rvlcdip` |
| DocVQA | Visual QA | `naver-clova-ix/donut-base-finetuned-docvqa` |

---

## Platform Support

| Platform | Status |
|----------|--------|
| Android | ✅ |
| iOS | ✅ |
| Web | ✅ |
| macOS | ✅ |
| Windows | ✅ |
| Linux | ✅ |

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

## References

- **PyMuPDF**: [github.com/pymupdf/PyMuPDF](https://github.com/pymupdf/PyMuPDF)
- **Donut**: Kim et al., *"OCR-free Document Understanding Transformer"*, ECCV 2022 — [arXiv:2111.15664](https://arxiv.org/abs/2111.15664) | [Code](https://github.com/clovaai/donut)
- **Swin Transformer**: Liu et al., *"Hierarchical Vision Transformer using Shifted Windows"*, ICCV 2021
- **BART**: Lewis et al., *"Denoising Sequence-to-Sequence Pre-training"*, ACL 2020
