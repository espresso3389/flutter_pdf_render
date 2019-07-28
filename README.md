## Introduction

[pdf_render](https://pub.dartlang.org/packages/pdf_render) is a PDF renderer implementation.

## Usage

The following fragment illustrate overall usage:

```dart
import 'package:pdf_render/pdf_render.dart';

...

/// Open the document using either openFile, openAsset, or openData.
PdfDocument doc = await PdfDocument.openAsset('assets/hello.pdf');

// Get the number of pages in the PDF file
int pageCount = doc.pageCount;

// The first page is 1
PdfPage page = await doc.getPage(1);

// For the render function's return, see explanation below.
PdfPageImage pageImage = await page.render();

// PDFDocument must be disposed as soon as possible.
doc.dispose();
```

And, then, you can use `PdfPageImage` to get the actual RGBA image in `dart.ui.Image`.

To embed the image in the widget tree, you can use [RawImage](https://docs.flutter.io/flutter/widgets/RawImage-class.html):

```dart
@override
Center(
  child: Container(
    padding: EdgeInsets.all(10.0),
    color: Colors.grey,
    child: Center(
      child: RawImage(image: pageImage.image, fit: BoxFit.contain))
  )
)
```

## PdfDocument.openXXX

On `PdfDocument` class, there're three functions for opening PDF from a real file, or a asset file, or memory data.

```dart
// from an asset file
PdfDocument docFromFile = PdfDocument.openAsset('assets/hello.pdf');

// from a file
PdfDocument docFromAsset = PdfDocument.openFile('/somewhere/in/real/file/system/file.pdf');

// from PDF memory image on Uint8List
PdfDocument docFromData = PdfDocument.openData(data);
```

## PdfDocument members

```dart
class PdfDocument {
  final int docId; // For internal purpose
  final int pageCount; // Number of pages in the document
  final int verMajor; // PDF major version
  final int verMinor; // PDF minor version
  final bool isEncrypted; // Whether the file is encrypted or not
  final bool allowsCopying; // Whether the file allows you to copy the texts
  final bool allowsPrinting; // Whether the file allows you to print the document

  // Get a page by page number (page number starts at 1)
  Future<PdfPage> getPage(int pageNumber);

  // Dispose the instance.
  void dispose();
}
```

## PdfPage members

```dart
class PdfPage {
  final int docId; // For internal purpose
  final int pageNumber; // Page number (page number starts at 1)
  final int rotationAngle; // Rotation angle; one of 0, 90, 180, 270
  final double width; // Page width in points; pixel size on 72-dpi
  final double height; // Page height in points; pixel size on 72-dpi

  // render sub-region of the PDF page.
  Future<PdfPageImage> render({
    int x = 0, int y = 0,
    int width = 0, int height = 0,
    double fullWidth = 0.0, double fullHeight = 0.0 });
```

For `render` function extract a sub-region `(x,y)` - `(x + width, y + height)` of scaled (`fullWidth` x `fullHeight`) PDF page image. All the coordinates are in pixels.

The following fragment renders the page at 300 dpi:

```dart
const scale = 300.0 / 72.0;
const fullWidth = page.width * scale;
const fullHeight = page.height * scale;
var rendered = page.render(
  x: 0,
  y: 0,
  width: fullWidth.toInt(),
  height: fullHeight.toInt(),
  fullWidth: fullWidth,
  fullHeight: fullHeight);
```

## PdfPageImage members

```dart
/// Page number. The first page is 1.
final int pageNumber;
/// Left X coordinate of the rendered area in pixels.
final int x;
/// Top Y coordinate of the rendered area in pixels.
final int y;
/// Width of the rendered area in pixels.
final int width;
/// Height of the rendered area in pixels.
final int height;
/// Full width of the rendered page image in pixels.
final int fullWidth;
/// Full height of the rendered page image in pixels.
final int fullHeight;
/// PDF page width in points (width in pixels at 72 dpi).
final double pageWidth;
/// PDF page height in points (height in pixels at 72 dpi).
final double pageHeight;
/// Rendered image in dart:ui.Image
final Image image;
```
