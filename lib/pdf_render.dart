import 'dart:async';
import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _channel = const MethodChannel('pdf_render');

class PdfDocument {
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

  Future<void> dispose() async {
    await _channel.invokeMethod('close', docId);
  }

  static PdfDocument _open(Object obj, String sourceName) {
    if (obj is Map<dynamic, dynamic>) {
      final pageCount = obj['pageCount'] as int;
      return PdfDocument(
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
      if (obj is Map<dynamic, dynamic>) {
        page = _pages[pageNumber - 1] = PdfPage(
          document: this,
          pageNumber: pageNumber,
          rotationAngle: obj['rotationAngle'] as int,
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

class PdfPage {
  final PdfDocument document;
  /// Page number. The first page is 1.
  final int pageNumber;
  /// Clockwise page rotation angle in degrees.
  final int rotationAngle;
  /// PDF page width in points (width in pixels at 72 dpi) (rotated).
  final double width;
  /// PDF page height in points (height in pixels at 72 dpi) (rotated).
  final double height;

  PdfPage({this.document, this.pageNumber, this.rotationAngle, this.width, this.height});

  /// Render a sub-area or full image of specified PDF file.
  /// [x], [y], [width], [height] specify sub-area to render in pixels.
  /// [fullWidth], [fullHeight] specify virtual full size of the page to render in pixels. If they're not specified, [width] and [height] are used to specify the full size.
  /// If [width], [height], [fullWidth], [fullHeight], and [dpi] are all 0, the page is rendered at 72 dpi.
  /// By default, [backgroundFill] is true and the page background is once filled with white before rendering page image but you can turn it off if needed.
  /// ![](./images/render-params.png)
  Future<PdfPageImage> render({int x, int y, int width, int height, double fullWidth, double fullHeight, bool backgroundFill}) async {
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
  /// Rendered image.
  final Image image;

  PdfPageImage({this.pageNumber, this.x, this.y, this.width, this.height, this.fullWidth, this.fullHeight, this.pageWidth, this.pageHeight, this.image});

  void dispose() {
    image?.dispose();
  }

  static Future<PdfPageImage> _render(
    PdfDocument document, int pageNumber,
    { int x , int y, int width, int height,
      double fullWidth, double fullHeight,
      bool backgroundFill,
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
      final pixels = obj['data'] as Uint8List;
      var image = await _decodeRgba(retWidth, retHeight, pixels);

      return PdfPageImage(
        pageNumber: obj['pageNumber'] as int,
        x: obj['x'] as int,
        y: obj['y'] as int,
        width: retWidth,
        height: retHeight,
        fullWidth: obj['fullWidth'] as double,
        fullHeight: obj['fullHeight'] as double,
        pageWidth: obj['pageWidth'] as double,
        pageHeight: obj['pageHeight'] as double,
        image: image
      );
    }
    return null;
  }

  static Future<PdfPageImage> render(String filePath, int pageNumber,
    { int x, int y, int width, int height,
      double fullWidth, double fullHeight}) async {
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

/// Very limited support for Flutter's [Texture] based drawing.
/// Because it does not transfer the rendered image via platform channel,
/// it could be faster and more efficient than the [PdfPageImage] based rendrering process.
class PdfPageImageTexture {
  final PdfDocument pdfDocument;
  final int pageNumber;
  final int texId;

  bool operator ==(Object other) {
    return other is PdfPageImageTexture &&
      other.pdfDocument == pdfDocument &&
      other.pageNumber == pageNumber;
  }

  int get hashCode => pdfDocument.docId ^ pageNumber;

  PdfPageImageTexture._({this.pdfDocument, this.pageNumber, this.texId});

  /// Create a new Flutter [Texture]. The object should be released by calling [dispose] method after use it.
  static Future<PdfPageImageTexture> create({@required PdfDocument pdfDocument, @required int pageNumber}) async {
    final texId = await _channel.invokeMethod<int>('allocTex');
    return PdfPageImageTexture._(pdfDocument: pdfDocument, pageNumber: pageNumber, texId: texId);
  }

  /// Release the object.
  Future<void> dispose() async {
    await _channel.invokeMethod('releaseTex', texId);
  }

  /// Update texture's sub-rectangle ([destX],[destY],[width],[height]) with the sub-rectangle ([srcX],[srcY],[width],[height]) of the PDF page scaled to [fullWidth] x [fullHeight] size.
  /// If [backgroundFill] is true, the sub-rectangle is filled with white before rendering the page content.
  /// The method can also resize the texture if you specify [texWidth] and [texHeight].
  Future<void> updateRect({int destX = 0, int destY = 0, int width, int height, int srcX = 0, int srcY = 0, int texWidth, int texHeight, double fullWidth, double fullHeight, bool backgroundFill = true}) async {
    await _channel.invokeMethod('updateTex', {
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
    });
  }
}
