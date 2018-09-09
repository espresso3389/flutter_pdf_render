import 'dart:async';
import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class PdfDocument {
  static const MethodChannel _channel = const MethodChannel('pdf_render');

  final String sourceName;
  final int docId;
  final int pageCount;
  final int verMajor;
  final int verMinor;
  final bool isEncrypted;
  final bool allowsCopying;
  final bool allowsPrinting;
  //final bool isUnlocked;

  final List<PdfPage> _pages;

  PdfDocument({
    this.sourceName,
    this.docId,
    this.pageCount,
    this.verMajor, this.verMinor,
    this.isEncrypted, this.allowsCopying, this.allowsPrinting,
    //this.isUnlocked,
  }) : _pages = List<PdfPage>(pageCount);

  void dispose() {
    _close();
  }

  void _close() {
    _channel.invokeMethod('close', docId);
  }

  static PdfDocument _open(Object obj, String sourceName) {
    var dict = obj as Map<dynamic, dynamic>;
    if (dict == null)
      return null;
    final pageCount = dict['pageCount'] as int;
    return PdfDocument(
      sourceName: sourceName,
      docId: dict['docId'] as int,
      pageCount: pageCount,
      verMajor: dict['verMajor'] as int,
      verMinor: dict['verMinor'] as int,
      isEncrypted: dict['isEncrypted'] as bool,
      allowsCopying: dict['allowsCopying'] as bool,
      allowsPrinting: dict['allowsPrinting'] as bool,
      //isUnlocked: dict['isUnlocked'] as bool
    );
  }

  static Future<PdfDocument> openFile(String filePath) async {
    return _open(await _channel.invokeMethod('file', filePath), filePath);
  }

  static Future<PdfDocument> openAsset(String name) async {
    return _open(await _channel.invokeMethod('asset', name), 'asset:' + name);
  }

  static Future<PdfDocument> openData(Uint8List data) async {
    return _open(await _channel.invokeMethod('data', data), 'memory:$data');
  }

  /// Get page object. The first page is 1.
  Future<PdfPage> getPage(int pageNumber) async {
    if (pageNumber < 1 || pageNumber > pageCount)
      return null;
    var page = _pages[pageNumber - 1];
    if (page == null) {
      var obj = await _channel.invokeMethod('page', {
        "docId": docId,
        "pageNumber": pageNumber
      });
      var dict = obj as Map<dynamic, dynamic>;
      if (dict == null)
        return null;
      page = _pages[pageNumber - 1] = PdfPage(
        document: this,
        pageNumber: pageNumber,
        rotationAngle: dict['rotationAngle'] as int,
        width: dict['width'] as double,
        height: dict['height'] as double,
      );
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

class PdfPage {
  final PdfDocument document;
  final int pageNumber;
  final int rotationAngle;
  final double width;
  final double height;

  PdfPage({this.document, this.pageNumber, this.rotationAngle, this.width, this.height});

  /// Render a sub-area or full image of specified PDF file.
  /// [pdfFilePath] specifies PDF file to open.
  /// [pageNumber] specifies page to render in page number (1 is the first page).
  /// [x], [y], [width], [height] specify sub-area to render in pixels.
  /// [fullWidth], [fullHeight] specify virtual full size of the page to render in pixels. If they're not specified, [width] and [height] are used to specify the full size.
  /// If [dpi] is set, [fullWidth] and [fullHeight] are ignored and the page is rendered in the specified dpi.
  /// If [boxFit] is set, the page image is rendered in a size, that fits into the box specified by [fullWidth], [fullHeight].
  /// If [width], [height], [fullWidth], [fullHeight], and [dpi] are all 0, the page is rendered at 72 dpi.
  Future<PdfPageImage> render({int x = 0, int y = 0, int width = 0, int height = 0, double fullWidth = 0.0, double fullHeight}) async {
    return PdfPageImage._render(
      document, pageNumber,
      x: x, y: y,
      width: width,
      height: height,
      fullWidth: fullWidth, fullHeight: fullHeight
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
  static const MethodChannel _channel = const MethodChannel('pdf_render');

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
  /// Rendered image.
  final Image image;

  PdfPageImage({this.pageNumber, this.x, this.y, this.width, this.height, this.fullWidth, this.fullHeight, this.pageWidth, this.pageHeight, this.image});

  void dispose() {
    image?.dispose();
  }

  static Future<PdfPageImage> _render(
    PdfDocument document, int pageNumber,
    { int x = 0, int y = 0, int width = 0, int height = 0,
      double fullWidth = 0.0, double fullHeight = 0.0
    }) async {
    var obj = await _channel.invokeMethod(
      'render',
      {
        'docId': document.docId, 'pageNumber': pageNumber,
        'x': x, 'y': y, 'width': width, 'height': height,
        'fullWidth': fullWidth, 'fullHeight': fullHeight
      });

    var dict = obj as Map<dynamic, dynamic>;
    if (dict == null)
      return null;
    final retWidth = dict['width'] as int;
    final retHeight = dict['height'] as int;
    final pixels = dict['data'] as Uint8List;
    var image = await _decodeRgba(retWidth, retHeight, pixels);

    return PdfPageImage(
      pageNumber: dict['pageNumber'] as int,
      x: dict['x'] as int,
      y: dict['y'] as int,
      width: retWidth,
      height: retHeight,
      fullWidth: dict['fullWidth'] as double,
      fullHeight: dict['fullHeight'] as double,
      pageWidth: dict['pageWidth'] as double,
      pageHeight: dict['pageHeight'] as double,
      image: image
    );
  }

  static Future<PdfPageImage> render(String filePath, int pageNumber,
    { int x = 0, int y = 0, int width = 0, int height = 0,
      double fullWidth = 0.0, double fullHeight = 0.0}) async {
    final doc = await PdfDocument.openFile(filePath);
    if (doc == null) return null;
    final page = await doc.getPage(pageNumber);
    final image = await page.render(
      x: x, y: y,
      width: width,
      height: height,
      fullWidth: fullWidth, fullHeight: fullHeight);
    doc.dispose();
    return image;
  }

  /// Decode RGBA raw image from native code.
  static Future<Image> _decodeRgba(
    int width, int height, Uint8List pixels) {
    final comp = Completer<Image>();
    decodeImageFromPixels(pixels, width, height, PixelFormat.rgba8888,
      (image) => comp.complete(image));
    return comp.future;
  }
}