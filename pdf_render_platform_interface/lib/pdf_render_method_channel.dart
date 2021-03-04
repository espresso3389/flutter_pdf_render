import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'utils/ffi_wrapper.dart';

import 'pdf_render.dart';
import 'pdf_render_platform_interface.dart';

const MethodChannel _channel = const MethodChannel('pdf_render');

class PdfRenderPlatformMethodChannel extends PdfRenderPlatform {
  PdfDocument? _open(Object? obj, String sourceName) {
    if (obj is Map<dynamic, dynamic>) {
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
    } else {
      return null;
    }
  }

  /// Opening the specified file.
  @override
  Future<PdfDocument?> openFile(String filePath) async {
    return _open(await _channel.invokeMethod('file', filePath), filePath);
  }

  /// Opening the specified asset.
  @override
  Future<PdfDocument?> openAsset(String name) async {
    return _open(await _channel.invokeMethod('asset', name), 'asset:$name');
  }

  /// Opening the PDF on memory.
  @override
  Future<PdfDocument?> openData(Uint8List data) async {
    return _open(await _channel.invokeMethod('data', data), 'memory:');
  }

  /// Create a new Flutter [Texture]. The object should be released by calling [dispose] method after use it.
  @override
  Future<PdfPageImageTexture> createTexture({required PdfDocument pdfDocument, required int pageNumber}) async {
    final texId = await _channel.invokeMethod<int>('allocTex');
    return PdfPageImageTextureMethodChannel._(pdfDocument: pdfDocument, pageNumber: pageNumber, texId: texId!);
  }
}

/// Handles PDF document loaded on memory.
class PdfDocumentMethodChannel extends PdfDocument {
  /// Document-ID that uniquely identifies the current instance.
  final int docId;

  final List<PdfPage?> _pages;

  PdfDocumentMethodChannel._({
    required String sourceName,
    required int docId,
    required int pageCount,
    required int verMajor,
    required int verMinor,
    required bool isEncrypted,
    required bool allowsCopying,
    required bool allowsPrinting,
  })   : docId = docId,
        _pages = List<PdfPage?>.filled(pageCount, null),
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
  Future<PdfPage?> getPage(int pageNumber) async {
    if (pageNumber < 1 || pageNumber > pageCount) return null;
    var page = _pages[pageNumber - 1];
    if (page == null) {
      var obj = await _channel.invokeMethod('page', {"docId": docId, "pageNumber": pageNumber});
      if (obj is Map<dynamic, dynamic>) {
        page = _pages[pageNumber - 1] = PdfPageMethodChannel._(
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
  bool operator ==(dynamic other) => other is PdfDocumentMethodChannel && other.docId == docId;

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
      : super(document: document, pageNumber: pageNumber, width: width, height: height);

  @override
  Future<PdfPageImage?> render({
    int? x,
    int? y,
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
      other is PdfPageMethodChannel && other.document == document && other.pageNumber == pageNumber;

  @override
  int get hashCode => document.hashCode ^ pageNumber;

  @override
  String toString() => '$document:page=$pageNumber';
}

class PdfPageImageMethodChannel extends PdfPageImage {
  Uint8List _pixels;
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

  /// Pointer to the inernal RGBA image buffer if available; the size is calculated by `width*height*4`.
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
  Future<ui.Image?> createImageIfNotAvailable() async {
    _imageCached ??= await _decodeRgba(width, height, _pixels);
    return _imageCached;
  }

  /// Get [Image] for the object if available; otherwise null.
  /// If you want to ensure that the [Image] is available, call [createImageIfNotAvailable].
  @override
  ui.Image? get imageIfAvailable => _imageCached;

  @override
  Future<ui.Image> createImageDetached() async => await _decodeRgba(width, height, _pixels);

  static Future<PdfPageImage?> _render(
    PdfDocumentMethodChannel document,
    int? pageNumber, {
    int? x,
    int? y,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    bool? backgroundFill,
    bool? allowAntialiasingIOS,
  }) async {
    var obj = await _channel.invokeMethod('render', {
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
    return null;
  }

  static Future<PdfPageImage?> render(String filePath, int pageNumber,
      {int x = 0,
      int y = 0,
      int? width,
      int? height,
      double? fullWidth,
      double? fullHeight,
      bool backgroundFill = true,
      bool allowAntialiasingIOS = false}) async {
    final doc = await PdfDocument.openFile(filePath);
    if (doc == null) return null;
    final page = await (doc.getPage(pageNumber) as FutureOr<PdfPage>);
    final image = await page.render(
        x: x,
        y: y,
        width: width,
        height: height,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
        backgroundFill: backgroundFill,
        allowAntialiasingIOS: allowAntialiasingIOS);
    doc.dispose();
    return image;
  }

  /// Decode RGBA raw image from native code.
  static Future<ui.Image> _decodeRgba(int width, int height, Uint8List pixels) {
    final comp = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, (image) => comp.complete(image));
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

  PdfPageImageTextureMethodChannel._({required PdfDocument pdfDocument, required int pageNumber, required int texId})
      : super(pdfDocument: pdfDocument, pageNumber: pageNumber, texId: texId);

  /// Release the object.
  Future<void> dispose() async {
    await _channel.invokeMethod('releaseTex', texId);
  }

  /// Update texture's sub-rectangle ([destX],[destY],[width],[height]) with the sub-rectangle
  /// ([srcX],[srcY],[width],[height]) of the PDF page scaled to [fullWidth] x [fullHeight] size.
  /// If [backgroundFill] is true, the sub-rectangle is filled with white before rendering the page content.
  /// The method can also resize the texture if you specify [texWidth] and [texHeight].
  /// Returns true if succeeded.
  Future<bool> updateRect(
      {int destX = 0,
      int destY = 0,
      int? width,
      int? height,
      int srcX = 0,
      int srcY = 0,
      int? texWidth,
      int? texHeight,
      double? fullWidth,
      double? fullHeight,
      bool backgroundFill = true,
      bool allowAntialiasingIOS = true}) async {
    final result = await (_channel.invokeMethod<int>('updateTex', {
      'docId': _doc.docId,
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
      'backgroundFill': backgroundFill,
      'allowAntialiasingIOS': allowAntialiasingIOS,
    }) as FutureOr<int>);
    if (result >= 0) {
      _texWidth = texWidth ?? _texWidth;
      _texHeight = texHeight ?? _texHeight;
    }
    return result >= 0;
  }
}
