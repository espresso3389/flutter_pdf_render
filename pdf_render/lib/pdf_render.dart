import 'dart:async';
import 'dart:ffi';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/services.dart';

const MethodChannel _channel = const MethodChannel('pdf_render');

/// Handles PDF document loaded on memory.
class PdfDocument {
  /// File path, `asset:[ASSET_PATH]` or `memory:` depending on the content opened.
  final String sourceName;
  /// Document-ID that uniquely identifies the current instance.
  final int docId;
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
  //final bool isUnlocked;

  final List<PdfPage?> _pages;

  PdfDocument._({
    required this.sourceName,
    required this.docId,
    required this.pageCount,
    required this.verMajor,
    required this.verMinor,
    required this.isEncrypted,
    required this.allowsCopying,
    required this.allowsPrinting,
    //required this.isUnlocked,
  }) : _pages = List<PdfPage?>.filled(pageCount, null);

  Future<void> dispose() async {
    await _channel.invokeMethod('close', docId);
  }

  static PdfDocument? _open(Object? obj, String sourceName) {
    if (obj is Map<dynamic, dynamic>) {
      final pageCount = obj['pageCount'] as int;
      return PdfDocument._(
        sourceName: sourceName,
        docId: obj['docId'] as int,
        pageCount: pageCount,
        verMajor: obj['verMajor'] as int,
        verMinor: obj['verMinor'] as int,
        isEncrypted: obj['isEncrypted'] as bool,
        allowsCopying: obj['allowsCopying'] as bool,
        allowsPrinting: obj['allowsPrinting'] as bool,
        //isUnlocked: obj['isUnlocked'] as bool
      );
    } else {
      return null;
    }

  }

  /// Opening the specified file.
  static Future<PdfDocument?> openFile(String filePath) async {
    return _open(await _channel.invokeMethod('file', filePath), filePath);
  }

  /// Opening the specified asset.
  static Future<PdfDocument?> openAsset(String name) async {
    return _open(await _channel.invokeMethod('asset', name), 'asset:$name');
  }

  /// Opening the PDF on memory.
  static Future<PdfDocument?> openData(Uint8List data) async {
    return _open(await _channel.invokeMethod('data', data), 'memory:');
  }

  /// Get page object. The first page is 1.
  Future<PdfPage?> getPage(int pageNumber) async {
    if (pageNumber < 1 || pageNumber > pageCount)
      return null;
    var page = _pages[pageNumber - 1];
    if (page == null) {
      var obj = await _channel.invokeMethod('page', {
        "docId": docId,
        "pageNumber": pageNumber
      });
      if (obj is Map<dynamic, dynamic>) {
        page = _pages[pageNumber - 1] = PdfPage._(
          document: this,
          pageNumber: pageNumber,
          width: obj['width'] as double,
          height: obj['height'] as double,
        );
      }
    }
    return page;
  }

  @override
  bool operator ==(dynamic other) => other is PdfDocument &&
    other.docId == docId;

  @override
  int get hashCode => docId;

  @override
  String toString() => sourceName;
}

/// Handles a PDF page in [PDFDocument].
class PdfPage {
  /// PDF document.
  final PdfDocument document;
  /// Page number. The first page is 1.
  final int pageNumber;
  /// PDF page width in points (width in pixels at 72 dpi) (rotated).
  final double width;
  /// PDF page height in points (height in pixels at 72 dpi) (rotated).
  final double height;

  PdfPage._({required this.document, required this.pageNumber, required this.width, required this.height});

  /// Render a sub-area or full image of specified PDF file.
  /// [x], [y], [width], [height] specify sub-area to render in pixels.
  /// [fullWidth], [fullHeight] specify virtual full size of the page to render in pixels. If they're not specified, [width] and [height] are used to specify the full size.
  /// If [width], [height], [fullWidth], [fullHeight], and [dpi] are all 0, the page is rendered at 72 dpi.
  /// By default, [backgroundFill] is true and the page background is once filled with white before rendering page image but you can turn it off if needed.
  /// ![](./images/render-params.png)
  Future<PdfPageImage?> render({int? x, int? y, int? width, int? height, double? fullWidth, double? fullHeight, bool? backgroundFill}) async {
    return PdfPageImage._render(
      document, pageNumber,
      x: x,
      y: y,
      width: width,
      height: height,
      fullWidth: fullWidth,
      fullHeight: fullHeight,
      backgroundFill: backgroundFill
    );
  }

  @override
  bool operator ==(dynamic other) => other is PdfPage &&
    other.document == document &&
    other.pageNumber == pageNumber;

  @override
  int get hashCode => document.hashCode ^ pageNumber;

  @override
  String toString() => '$document:page=$pageNumber';
}

class PdfPageImage {
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

  Uint8List _pixels;
  Pointer<Uint8>? _buffer;
  ui.Image? _imageCached;

  PdfPageImage._({required this.pageNumber, required this.x, required this.y, required this.width, required this.height, required this.fullWidth, required this.fullHeight, required this.pageWidth, required this.pageHeight, required Uint8List pixels, Pointer<Uint8>? buffer}): _pixels = pixels, _buffer = buffer;

  /// RGBA pixels in byte array.
  Uint8List get pixels => _pixels;

  /// Pointer to the inernal RGBA image buffer if available; the size is calculated by `width*height*4`.
  Pointer<Uint8>? get buffer => _buffer;

  void dispose() {
    _imageCached?.dispose();
    _imageCached = null;
    if (_buffer != null) {
      _channel.invokeMethod('releaseBuffer', _buffer!.address);
      _buffer = null;
    }
  }

  /// Create cached [Image] for the page.
  Future<ui.Image?> createImageIfNotAvailable() async {
    _imageCached ??= await _decodeRgba(width, height, _pixels);
    return _imageCached;
  }

  /// Get [Image] for the object if available; otherwise null.
  /// If you want to ensure that the [Image] is available, call [createImageIfNotAvailable].
  ui.Image? get imageIfAvailable => _imageCached;

  Future<ui.Image> createImageDetached() async => await _decodeRgba(width, height, _pixels);

  static Future<PdfPageImage?> _render(
    PdfDocument document, int? pageNumber,
    { int? x , int? y, int? width, int? height,
      double? fullWidth, double? fullHeight,
      bool? backgroundFill,
    }) async {

    var obj = await _channel.invokeMethod(
      'render',
      {
        'docId': document.docId, 'pageNumber': pageNumber,
        'x': x, 'y': y, 'width': width, 'height': height,
        'fullWidth': fullWidth, 'fullHeight': fullHeight,
        'backgroundFill': backgroundFill
      });

    if (obj is Map<dynamic, dynamic>) {
      final retWidth = obj['width'] as int;
      final retHeight = obj['height'] as int;
      Pointer<Uint8>? ptr;
      var pixels = obj['data'] as Uint8List?;
      if (pixels == null) {
        final addr = obj['addr'] as int?;
        final size = obj['size'] as int?;
        if (addr != null && size != null) {
          ptr = Pointer<Uint8>.fromAddress(addr);
          pixels = ptr.asTypedList(size);
        } else {
          return null;
        }
      }

      return PdfPageImage._(
        pageNumber: obj['pageNumber'] as int,
        x: obj['x'] as int,
        y: obj['y'] as int,
        width: retWidth,
        height: retHeight,
        fullWidth: obj['fullWidth'] as double,
        fullHeight: obj['fullHeight'] as double,
        pageWidth: obj['pageWidth'] as double,
        pageHeight: obj['pageHeight'] as double,
        pixels: pixels,
        buffer: ptr
      );
    }
    return null;
  }

  static Future<PdfPageImage?> render(String filePath, int pageNumber,
    { int? x, int? y, int? width, int? height,
      double? fullWidth, double? fullHeight}) async {
    final doc = await PdfDocument.openFile(filePath);
    if (doc == null) return null;
    final page = await (doc.getPage(pageNumber) as FutureOr<PdfPage>);
    final image = await page.render(
      x: x, y: y,
      width: width,
      height: height,
      fullWidth: fullWidth, fullHeight: fullHeight);
    doc.dispose();
    return image;
  }

  /// Decode RGBA raw image from native code.
  static Future<ui.Image> _decodeRgba(
    int width, int height, Uint8List pixels) {
    final comp = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888,
      (image) => comp.complete(image));
    return comp.future;
  }
}

/// Very limited support for Flutter's [Texture] based drawing.
/// Because it does not transfer the rendered image via platform channel,
/// it could be faster and more efficient than the [PdfPageImage] based rendrering process.
class PdfPageImageTexture {
  final PdfDocument pdfDocument;
  final int pageNumber;
  final int texId;

  int? _texWidth;
  int? _texHeight;

  int? get texWidth => _texWidth;
  int? get texHeight => _texHeight;
  bool get hasUpdatedTexture => _texWidth != null;

  bool operator ==(Object other) {
    return other is PdfPageImageTexture &&
      other.pdfDocument == pdfDocument &&
      other.pageNumber == pageNumber;
  }

  int get hashCode => pdfDocument.docId ^ pageNumber;

  PdfPageImageTexture._({required this.pdfDocument, required this.pageNumber, required this.texId});

  /// Create a new Flutter [Texture]. The object should be released by calling [dispose] method after use it.
  static Future<PdfPageImageTexture> create({required PdfDocument pdfDocument, required int pageNumber}) async {
    final texId = await _channel.invokeMethod<int>('allocTex');
    return PdfPageImageTexture._(pdfDocument: pdfDocument, pageNumber: pageNumber, texId: texId!);
  }

  /// Release the object.
  Future<void> dispose() async {
    await _channel.invokeMethod('releaseTex', texId);
  }

  /// Update texture's sub-rectangle ([destX],[destY],[width],[height]) with the sub-rectangle ([srcX],[srcY],[width],[height]) of the PDF page scaled to [fullWidth] x [fullHeight] size.
  /// If [backgroundFill] is true, the sub-rectangle is filled with white before rendering the page content.
  /// The method can also resize the texture if you specify [texWidth] and [texHeight].
  /// Returns true if succeeded.
  Future<bool> updateRect({int destX = 0, int destY = 0, int? width, int? height, int srcX = 0, int srcY = 0, int? texWidth, int? texHeight, double? fullWidth, double? fullHeight, bool backgroundFill = true}) async {
    final result = await (_channel.invokeMethod<int>('updateTex', {
      'docId': pdfDocument.docId,
      'pageNumber': pageNumber,
      'texId': texId,
      'destX': destX,
      'destY': destY,
      'width': width,
      'height': height,
      'srcX': srcX,
      'srcY': srcY,
      'texWidth': texWidth,
      'texHeight': texHeight,
      'fullWidth': fullWidth,
      'fullHeight': fullHeight,
      'backgroundFill': backgroundFill
    }) as FutureOr<int>);
    if (result >= 0) {
      _texWidth = texWidth ?? _texWidth;
      _texHeight = texHeight ?? _texHeight;
    }
    return result >= 0;
  }
}
