import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'pdf_render_platform_interface.dart';
import "../utils/ffi_wrapper.dart";

/// Handles PDF document loaded on memory.
abstract class PdfDocument {
  /// File path, `asset:[ASSET_PATH]` or `memory:` depending on the content opened.
  final String sourceName;

  /// Number of pages in the PDF document.
  final int pageCount;

  /// PDF major version.
  final int verMajor;

  /// PDF minor version.
  final int verMinor;

  /// Determine whether the PDF file is encrypted or not.
  final bool isEncrypted;

  /// Determine whether the PDF file allows copying of the contents.
  final bool allowsCopying;

  /// Determine whether the PDF file allows printing of the pages.
  final bool allowsPrinting;

  PdfDocument({
    required this.sourceName,
    required this.pageCount,
    required this.verMajor,
    required this.verMinor,
    required this.isEncrypted,
    required this.allowsCopying,
    required this.allowsPrinting,
  });

  Future<void> dispose();

  /// Opening the specified file.
  /// For Web, [filePath] can be relative path from `index.html` or any arbitrary URL but it may be restricted by CORS.
  static Future<PdfDocument> openFile(String filePath) =>
      PdfRenderPlatform.instance.openFile(filePath);

  /// Opening the specified asset.
  static Future<PdfDocument> openAsset(String name) =>
      PdfRenderPlatform.instance.openAsset(name);

  /// Opening the PDF on memory.
  static Future<PdfDocument> openData(Uint8List data) =>
      PdfRenderPlatform.instance.openData(data);

  /// Get page object. The first page is 1.
  Future<PdfPage> getPage(int pageNumber);

  @override
  bool operator ==(dynamic other);

  @override
  int get hashCode;

  @override
  String toString() => sourceName;
}

/// Handles a PDF page in [PDFDocument].
abstract class PdfPage {
  /// PDF document.
  final PdfDocument document;

  /// Page number. The first page is 1.
  final int pageNumber;

  /// PDF page width in points (width in pixels at 72 dpi) (rotated).
  final double width;

  /// PDF page height in points (height in pixels at 72 dpi) (rotated).
  final double height;

  PdfPage({
    required this.document,
    required this.pageNumber,
    required this.width,
    required this.height,
  });

  /// Render a sub-area or full image of specified PDF file.
  /// [x], [y], [width], [height] specify sub-area to render in pixels.
  /// [fullWidth], [fullHeight] specify virtual full size of the page to render in pixels. If they're not specified, [width] and [height] are used to specify the full size.
  /// If [width], [height], [fullWidth], [fullHeight], and [dpi] are all 0, the page is rendered at 72 dpi.
  /// By default, [backgroundFill] is true and the page background is once filled with white before rendering page image but you can turn it off if needed.
  /// ![](./images/render-params.png)
  Future<PdfPageImage> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    bool backgroundFill = true,
    bool allowAntialiasingIOS = false,
  });

  @override
  bool operator ==(dynamic other) =>
      other is PdfPage &&
      other.document == document &&
      other.pageNumber == pageNumber;

  @override
  int get hashCode => document.hashCode ^ pageNumber;

  @override
  String toString() => '$document:page=$pageNumber';
}

abstract class PdfPageImage {
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
  final double fullWidth;

  /// Full height of the rendered page image in pixels.
  final double fullHeight;

  /// PDF page width in points (width in pixels at 72 dpi).
  final double pageWidth;

  /// PDF page height in points (height in pixels at 72 dpi).
  final double pageHeight;

  PdfPageImage(
      {required this.pageNumber,
      required this.x,
      required this.y,
      required this.width,
      required this.height,
      required this.fullWidth,
      required this.fullHeight,
      required this.pageWidth,
      required this.pageHeight});

  /// RGBA pixels in byte array.
  Uint8List get pixels;

  /// Pointer to the internal RGBA image buffer if available; the size is calculated by `width*height*4`.
  Pointer<Uint8>? get buffer;

  void dispose();

  /// Create cached [Image] for the page.
  Future<ui.Image> createImageIfNotAvailable();

  /// Get [Image] for the object if available; otherwise null.
  /// If you want to ensure that the [Image] is available, call [createImageIfNotAvailable].
  ui.Image? get imageIfAvailable;

  Future<ui.Image> createImageDetached();
}

/// Very limited support for Flutter's [Texture] based drawing.
/// Because it does not transfer the rendered image via platform channel,
/// it could be faster and more efficient than the [PdfPageImage] based rendering process.
abstract class PdfPageImageTexture {
  final PdfDocument pdfDocument;
  final int pageNumber;
  final int texId;

  int? get texWidth;
  int? get texHeight;
  bool get hasUpdatedTexture;

  @override
  bool operator ==(Object other);

  @override
  int get hashCode;

  PdfPageImageTexture(
      {required this.pdfDocument,
      required this.pageNumber,
      required this.texId});

  /// Create a new Flutter [Texture]. The object should be released by calling [dispose] method after use it.
  static Future<PdfPageImageTexture> create(
          {required FutureOr<PdfDocument> pdfDocument,
          required int pageNumber}) =>
      PdfRenderPlatform.instance
          .createTexture(pdfDocument: pdfDocument, pageNumber: pageNumber);

  /// Release the object.
  Future<void> dispose();

  /// Extract sub-rectangle ([x],[y],[width],[height]) of the PDF page scaled to [fullWidth] x [fullHeight] size.
  /// If [backgroundFill] is true, the sub-rectangle is filled with white before rendering the page content.
  /// [allowAntialiasingIOS] specifies whether to allow use of antialiasing on iOS Quartz PDF rendering
  /// Returns true if succeeded.
  Future<bool> extractSubrect({
    int x = 0,
    int y = 0,
    required int width,
    required int height,
    double? fullWidth,
    double? fullHeight,
    bool backgroundFill = true,
    bool allowAntialiasingIOS = true,
  });
}
