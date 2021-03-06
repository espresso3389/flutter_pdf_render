import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import '../wrappers/html.dart' as html;
import '../wrappers/js_util.dart' as js_util;
import 'pdf.js.dart';

class PdfRenderWebPlugin {
  static void registerWith(Registrar registrar) {
    final channel = MethodChannel('pdf_render', const StandardMethodCodec(), registrar);
    final plugin = PdfRenderWebPlugin._();
    channel.setMethodCallHandler(plugin.handleMethodCall);
  }

  PdfRenderWebPlugin._() {
    _eventChannel.setController(_eventStreamController);
  }

  // NOTE: No-one calls the method anyway...
  void dispose() {
    _eventStreamController.close();
  }

  final _eventStreamController = StreamController<int>();
  final _eventChannel = PluginEventChannel('jp.espresso3389.pdf_render/web_texture_events');
  final _docs = Map<int, PdfjsDocument>();
  int _lastDocId = -1;
  final _textures = Map<int, RgbaData>();
  int _texId = -1;

  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'file':
        throw Exception('`file` is not implemented yet.');
      case 'asset':
        {
          final assetPath = call.arguments as String;
          final bytes = await rootBundle.load(assetPath);
          final doc = await pdfjsGetDocumentFromData(bytes.buffer);
          return _setDoc(doc);
        }
      case 'data':
        {
          final doc = await pdfjsGetDocumentFromData(call.arguments as ByteBuffer);
          return _setDoc(doc);
        }
      case 'close':
        _docs.remove(call.arguments as int)?.destroy();
        break;
      case 'info':
        return _getDoc(call.arguments as int);
      case 'page':
        return await _openPage(call.arguments);
      case 'allocTex':
        return _allocTex();
      case 'releaseTex':
        return _releaseTex(call.arguments as int);
      case 'resizeTex':
        return _resizeTex(call.arguments);
      case 'updateTex':
        return await _updateTex(call.arguments);
      default:
        throw Exception('`${call.method}` is not supported.');
    }
  }

  dynamic _setDoc(PdfjsDocument doc) {
    _docs[++_lastDocId] = doc;
    return _getDoc(_lastDocId);
  }

  dynamic _getDoc(int id) {
    final doc = _docs[id];
    return {
      'docId': id,
      'pageCount': doc!.numPages,
      'verMajor': 1,
      'verMinor': 7,
      'isEncrypted': false,
      'allowsCopying': false,
      'allowsPrinting': false
    };
  }

  dynamic _openPage(dynamic args) async {
    final docId = args['docId'] as int;
    final doc = _docs[docId]!;
    final pageNumber = args['pageNumber'] as int;
    if (pageNumber < 1 || pageNumber > doc.numPages) return null;
    final page = await js_util.promiseToFuture<PdfjsPage>(doc.getPage(pageNumber));
    final vp1 = page.getViewport(PdfjsViewportParams(scale: 1));
    return {
      'docId': docId,
      'pageNumber': pageNumber,
      'width': vp1.width,
      'height': vp1.height,
    };
  }

  int _allocTex() {
    return ++_texId;
  }

  void _releaseTex(int id) {
    _textures.remove(id);
    js_util.setProperty(html.window, 'pdf_render_texture_$id', null);
  }

  int _resizeTex(dynamic args) {
    final id = args['texId'] as int;
    final canvas = _textures[id];
    if (canvas == null) return -1;
    final width = args['width'] as int;
    final height = args['height'] as int;
    _updateTexSize(id, width, height);

    _eventStreamController.sink.add(id);
    return 0;
  }

  RgbaData _updateTexSize(int id, int width, int height) {
    final oldData = _textures[id];
    if (oldData != null && oldData.width == width && oldData.height == height) {
      return oldData;
    }
    final data = _textures[id] = RgbaData.alloc(id: id, width: width, height: height);
    js_util.setProperty(html.window, 'pdf_render_texture_$id', data);
    return data;
  }

  Future<int> _updateTex(dynamic args) async {
    final id = args['texId'] as int;
    final docId = args['docId'] as int;
    final doc = _docs[docId];
    if (doc == null) return -3;
    final pageNumber = args['pageNumber'] as int;
    if (pageNumber < 1 || pageNumber > doc.numPages) return -6;
    final page = await js_util.promiseToFuture<PdfjsPage>(doc.getPage(pageNumber));

    final vp1 = page.getViewport(PdfjsViewportParams(scale: 1));
    final pw = vp1.width;
    final ph = vp1.height;
    final fullWidth = args['fullWidth'] as double? ?? pw;
    //final fullHeight = args['fullHeight'] as double? ?? ph;
    final destX = args['destX'] as int? ?? 0;
    final destY = args['destY'] as int? ?? 0;
    final width = args['width'] as int?;
    final height = args['height'] as int?;
    final backgroundFill = args['backgroundFill'] as bool? ?? true;
    if (width == null || height == null || width <= 0 || height <= 0) return -7;

    final offsetX = -(args['srcX'] as int? ?? 0).toDouble();
    final offsetY = -(args['srcY'] as int? ?? 0).toDouble();

    final vp = page.getViewport(PdfjsViewportParams(
      scale: fullWidth / pw,
      offsetX: offsetX,
      offsetY: offsetY,
      dontFlip: false,
    ));

    final data = _updateTexSize(id, args['texWidth'] as int, args['texHeight'] as int);
    final canvas = html.document.createElement('canvas') as html.CanvasElement;
    canvas.width = width;
    canvas.height = height;

    if (backgroundFill) {
      canvas.context2D.fillStyle = 'white';
      canvas.context2D.fillRect(0, 0, width, height);
    }

    await js_util.promiseToFuture(page
        .render(
          PdfjsRenderContext(
            canvasContext: canvas.context2D,
            viewport: vp,
          ),
        )
        .promise);

    final src = canvas.context2D.getImageData(0, 0, width, height).data.buffer.asUint8List();

    final destStride = data.stride;
    final bpl = width * 4;
    int dp = data.getOffset(destX, destY);
    int sp = bpl * (height - 1);
    for (int y = 0; y < height; y++) {
      for (int i = 0; i < bpl; i++) {
        data.data[dp + i] = src[sp + i];
      }
      dp += destStride;
      sp -= bpl;
    }

    _eventStreamController.sink.add(id);
    return 0;
  }
}

@immutable
class RgbaData {
  final int id;
  final int width;
  final int height;
  final Uint8List data;

  int get stride => width * 4;
  int getOffset(int x, int y) => (x + y * width) * 4;

  RgbaData(this.id, this.width, this.height, this.data);

  factory RgbaData.alloc({
    required int id,
    required int width,
    required int height,
  }) =>
      RgbaData(
        id,
        width,
        height,
        Uint8List(width * 4 * height),
      );

  @override
  String toString() => 'RgbaData(id=$id, $width x $height)';
}
