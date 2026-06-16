# Snag Report Extractor

A cross-platform Flutter app that extracts captioned **snag photos** from PDF
inspection reports. Drop in one or more PDFs, pick an output folder, and the app
pulls out every embedded image, finds its caption, renders the caption beneath
the photo, and saves the result as a PNG per image.

Built for desktop first (macOS / Windows / Linux), with Android, iOS and Web
targets configured.

---

## What it does

1. Add PDFs via drag-and-drop or the file picker.
2. Choose an output directory (persisted between launches).
3. Each PDF is processed in its own background **isolate**:
   - read page count and the per-page text/image layout,
   - extract each embedded image,
   - match a caption to each image (text sized 10pt positioned just below the
     image's bounding box),
   - render the caption under the image and write `image_<n>.png` to
     `<output>/<pdf name>/`.
4. Live per-file progress (current page, image count, ETA) and a logs screen.

---

## Tech stack

| Concern | Choice |
|---|---|
| UI / state | Flutter + **Riverpod 3** (`Notifier`/`NotifierProvider`) |
| Routing | `go_router` |
| Drag & drop / file picking | `desktop_drop`, `file_picker` 11 |
| Logging | `talker_flutter` (see the in-app logs screen) |
| Output-dir persistence | `shared_preferences` + `directory_bookmarks` (macOS security-scoped bookmarks) |
| Android storage | `saf_stream` / `saf_util` (Storage Access Framework) |
| PDF engine | see **PDF engine** below |

Requires the Flutter stable channel (Dart SDK `^3.12`, Flutter `>= 3.44`).

---

## Project layout

```
lib/                         Flutter app
  src/
    app.dart                 MaterialApp.router + theme
    routing/                 go_router config
    features/pdf_extractor/  the feature (presentation / data / domain)
    common_widgets/  constants/  logging/
packages/
  dart_mupdf_donut/          vendored, locally-patched pure-Dart PDF engine (path dep)
plugins/
  directory_bookmarks/       local macOS plugin (security-scoped bookmarks, SPM-ready)
tool/
  mupdf_spike.dart           standalone PDF-engine evaluation harness
  font_probe.dart            font/encoding diagnostics
```

---

## PDF engine

The extraction logic needs three things from a PDF: page count, **embedded
image bytes**, and **text with bounding boxes + font size** (to locate captions).

- **Current (legacy):** the app shells out to the external **`mutool`** (MuPDF)
  CLI via `Process`. ⚠️ Known issue: the macOS binary path is hardcoded in
  `lib/src/features/pdf_extractor/data/mupdf_repository.dart` and must be changed
  for your machine; there is no bundled binary yet.
- **In progress:** migrating to the vendored, MIT-licensed
  [`packages/dart_mupdf_donut`](packages/dart_mupdf_donut) (pure Dart, no native
  binary, all platforms). It has been patched locally to fix image filter-chain
  decoding, ToUnicode caption decoding, and image bounding boxes. Once the
  worker is switched over, `mutool` and the `clib/` + FFI scaffolding can be
  removed. See `tool/mupdf_spike.dart` for how the engine is exercised.

---

## Getting started

```bash
flutter pub get

# Run on your platform of choice
flutter run -d macos      # or windows / linux / chrome
```

### macOS note
The macOS app is **sandboxed** (`com.apple.security.app-sandbox`). The
`directory_bookmarks` plugin persists write access to the user-chosen output
folder across launches via security-scoped bookmarks. Swift Package Manager is
supported (CocoaPods still works as a fallback).

### While still on the legacy engine
Build/obtain `mutool` (from MuPDF) and update the path in `mupdf_repository.dart`
(macOS) or ensure `mutool.exe` is on `PATH` (Windows).

---

## Developer tools

```bash
# Evaluate the PDF engine against a sample (writes images to tool/spike_out/)
dart run tool/mupdf_spike.dart [path/to.pdf]

# Inspect a PDF's fonts / encodings
dart run tool/font_probe.dart [path/to.pdf]
```

---

## Notes

- Sample inspection PDFs (`assets/sample*.pdf`) and signing certificates are
  git-ignored — they contain private data and must not be committed.
- This is a private project (`publish_to: none`).
