import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'utils/ffi_wrapper.dart';

import 'interfaces/pdf_render.dart';
import 'interfaces/pdf_render_platform_interface.dart';

const MethodChannel _channel = MethodChannel('pdf_render');

class PdfRenderPlatformMethodChannel extends PdfRenderPlatform {
  PdfDocument _open(Map<dynamic, dynamic> obj, String sourceName) {
    final pageCount = obj['pageCount'] as int;
    return PdfDocumentMethodChannel._(
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
  }

  /// Opening the specified file.
  @override
  Future<PdfDocument> openFile(String filePath) async {
    return _open(await _channel.invokeMethod('file', filePath), filePath);
  }

  /// Opening the specified asset.
  @override
  Future<PdfDocument> openAsset(String name) async {
    return _open(await _channel.invokeMethod('asset', name), 'asset:$name');
  }

  /// Opening the PDF on memory.
  @override
  Future<PdfDocument> openData(Uint8List data) async {
    return _open(await _channel.invokeMethod('data', data), 'memory:');
  }

  /// Create a new Flutter [Texture]. The object should be released by calling [dispose] method after use it.
  @override
  Future<PdfPageImageTexture> createTexture(
      {required FutureOr<PdfDocument> pdfDocument,
      required int pageNumber}) async {
    final texId = await _channel.invokeMethod<int>('allocTex');
    return PdfPageImageTextureMethodChannel._(
        pdfDocument: await pdfDocument, pageNumber: pageNumber, texId: texId!);
  }
}

/// Handles PDF document loaded on memory.
class PdfDocumentMethodChannel extends PdfDocument {
  /// Document-ID that uniquely identifies the current instance.
  final int docId;

  final List<PdfPage?> _pages;

  PdfDocumentMethodChannel._({
    required String sourceName,
    required this.docId,
    required int pageCount,
    required int verMajor,
    required int verMinor,
    required bool isEncrypted,
    required bool allowsCopying,
    required bool allowsPrinting,
  })  : _pages = List<PdfPage?>.filled(pageCount, null),
        super(
            sourceName: sourceName,
            pageCount: pageCount,
            verMajor: verMajor,
            verMinor: verMinor,
            isEncrypted: isEncrypted,
            allowsCopying: allowsCopying,
            allowsPrinting: allowsPrinting);

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod('close', docId);
  }

  /// Get page object. The first page is 1.
  @override
  Future<PdfPage> getPage(int pageNumber) async {
    if (pageNumber < 1 || pageNumber > pageCount) {
      throw RangeError.range(pageNumber, 1, pageCount, 'pageNumber');
    }
    var page = _pages[pageNumber - 1];
    if (page == null) {
      var obj = (await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'page', {"docId": docId, "pageNumber": pageNumber}))!;
      page = _pages[pageNumber - 1] = PdfPageMethodChannel._(
        document: this,
        pageNumber: pageNumber,
        width: obj['width'] as double,
        height: obj['height'] as double,
      );
    }
    return page;
  }

  @override
  bool operator ==(dynamic other) =>
      other is PdfDocumentMethodChannel && other.docId == docId;

  @override
  int get hashCode => docId;

  @override
  String toString() => sourceName;
}

/// Handles a PDF page in [PDFDocument].
class PdfPageMethodChannel extends PdfPage {
  PdfPageMethodChannel._(
      {required PdfDocumentMethodChannel document,
      required int pageNumber,
      required double width,
      required double height})
      : super(
            document: document,
            pageNumber: pageNumber,
            width: width,
            height: height);

  @override
  Future<PdfPageImage> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    bool? backgroundFill,
    bool? allowAntialiasingIOS,
  }) async {
    return PdfPageImageMethodChannel._render(
      document as PdfDocumentMethodChannel,
      pageNumber,
      x: x,
      y: y,
      width: width,
      height: height,
      fullWidth: fullWidth,
      fullHeight: fullHeight,
      backgroundFill: backgroundFill,
      allowAntialiasingIOS: allowAntialiasingIOS,
    );
  }

  @override
  bool operator ==(dynamic other) =>
      other is PdfPageMethodChannel &&
      other.document == document &&
      other.pageNumber == pageNumber;

  @override
  int get hashCode => document.hashCode ^ pageNumber;

  @override
  String toString() => '$document:page=$pageNumber';
}

class PdfPageImageMethodChannel extends PdfPageImage {
  final Uint8List _pixels;
  Pointer<Uint8>? _buffer;
  ui.Image? _imageCached;

  PdfPageImageMethodChannel._(
      {required int pageNumber,
      required int x,
      required int y,
      required int width,
      required int height,
      required double fullWidth,
      required double fullHeight,
      required double pageWidth,
      required double pageHeight,
      required Uint8List pixels,
      Pointer<Uint8>? buffer})
      : _pixels = pixels,
        _buffer = buffer,
        super(
            pageNumber: pageNumber,
            x: x,
            y: y,
            width: width,
            height: height,
            fullWidth: fullWidth,
            fullHeight: fullHeight,
            pageWidth: pageWidth,
            pageHeight: pageHeight);

  /// RGBA pixels in byte array.
  @override
  Uint8List get pixels => _pixels;

  /// Pointer to the internal RGBA image buffer if available; the size is calculated by `width*height*4`.
  @override
  Pointer<Uint8>? get buffer => _buffer;

  @override
  void dispose() {
    _imageCached?.dispose();
    _imageCached = null;
    if (_buffer != null) {
      _channel.invokeMethod('releaseBuffer', _buffer!.address);
      _buffer = null;
    }
  }

  /// Create cached [Image] for the page.
  @override
  Future<ui.Image> createImageIfNotAvailable() async {
    _imageCached ??= await _decodeRgba(width, height, _pixels);
    return _imageCached!;
  }

  /// Get [Image] for the object if available; otherwise null.
  /// If you want to ensure that the [Image] is available, call [createImageIfNotAvailable].
  @override
  ui.Image? get imageIfAvailable => _imageCached;

  @override
  Future<ui.Image> createImageDetached() async =>
      await _decodeRgba(width, height, _pixels);

  static Future<PdfPageImage> _render(
    PdfDocumentMethodChannel document,
    int pageNumber, {
    int? x,
    int? y,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    bool? backgroundFill,
    bool? allowAntialiasingIOS,
  }) async {
    final obj = (await _channel.invokeMethod<Map<dynamic, dynamic>>('render', {
      'docId': document.docId,
      'pageNumber': pageNumber,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'fullWidth': fullWidth,
      'fullHeight': fullHeight,
      'backgroundFill': backgroundFill,
      'allowAntialiasingIOS': allowAntialiasingIOS,
    }))!;

    final retWidth = obj['width'] as int;
    final retHeight = obj['height'] as int;
    Pointer<Uint8>? ptr;
    var pixels = obj['data'] as Uint8List? ??
        () {
          final addr = obj['addr'] as int;
          final size = obj['size'] as int;
          ptr = Pointer<Uint8>.fromAddress(addr);
          return ptr!.asTypedList(size);
        }();

    return PdfPageImageMethodChannel._(
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
        buffer: ptr);
  }

  /// Decode RGBA raw image from native code.
  static Future<ui.Image> _decodeRgba(int width, int height, Uint8List pixels) {
    final comp = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888,
        (image) => comp.complete(image));
    return comp.future;
  }
}

/// Very limited support for Flutter's [Texture] based drawing.
/// Because it does not transfer the rendered image via platform channel,
/// it could be faster and more efficient than the [PdfPageImage] based rendering process.
class PdfPageImageTextureMethodChannel extends PdfPageImageTexture {
  int? _texWidth;
  int? _texHeight;

  @override
  int? get texWidth => _texWidth;
  @override
  int? get texHeight => _texHeight;
  @override
  bool get hasUpdatedTexture => _texWidth != null;

  @override
  bool operator ==(Object other) {
    return other is PdfPageImageTextureMethodChannel &&
        other.pdfDocument == pdfDocument &&
        other.pageNumber == pageNumber;
  }

  PdfDocumentMethodChannel get _doc => pdfDocument as PdfDocumentMethodChannel;

  @override
  int get hashCode => _doc.docId ^ pageNumber;

  PdfPageImageTextureMethodChannel._(
      {required PdfDocument pdfDocument,
      required int pageNumber,
      required int texId})
      : super(pdfDocument: pdfDocument, pageNumber: pageNumber, texId: texId);

  /// Release the object.
  @override
  Future<void> dispose() => _channel.invokeMethod('releaseTex', texId);

  /// Extract sub-rectangle ([x],[y],[width],[height]) of the PDF page scaled to [fullWidth] x [fullHeight] size.
  /// If [backgroundFill] is true, the sub-rectangle is filled with white before rendering the page content.
  /// Returns true if succeeded.
  /// Returns true if succeeded.
  @override
  Future<bool> extractSubrect(
      {int x = 0,
      int y = 0,
      required int width,
      required int height,
      double? fullWidth,
      double? fullHeight,
      bool backgroundFill = true,
      bool allowAntialiasingIOS = true}) async {
    final result = (await _channel.invokeMethod<int>('updateTex', {
      'docId': _doc.docId,
      'pageNumber': pageNumber,
      'texId': texId,
      'width': width,
      'height': height,
      'srcX': x,
      'srcY': y,
      'fullWidth': fullWidth,
      'fullHeight': fullHeight,
      'backgroundFill': backgroundFill,
      'allowAntialiasingIOS': allowAntialiasingIOS,
    }))!;
    if (result >= 0) {
      _texWidth = width;
      _texHeight = height;
    }
    return result >= 0;
  }
}
