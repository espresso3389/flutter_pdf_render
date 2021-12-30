import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import '../utils/web_pointer.dart';
import '../wrappers/html.dart' as html;
import '../wrappers/js_util.dart' as js_util;
import '../wrappers/impls/pdf_texture_web.dart';
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
  final _eventChannel = const PluginEventChannel('jp.espresso3389.pdf_render/web_texture_events');
  final _docs = <int, PdfjsDocument>{};
  int _lastDocId = -1;
  final _textures = <int, RgbaData>{};
  int _texId = -1;

  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'file':
        {
          final doc = await pdfjsGetDocument(call.arguments as String);
          return _setDoc(doc);
        }
      case 'asset':
        {
          final assetPath = call.arguments as String;
          final bytes = await rootBundle.load(assetPath);
          final doc = await pdfjsGetDocumentFromData(bytes.buffer);
          return _setDoc(doc);
        }
      case 'data':
        {
          final doc = await pdfjsGetDocumentFromData((call.arguments as Uint8List).buffer);
          return _setDoc(doc);
        }
      case 'close':
        _docs.remove(call.arguments as int)?.destroy();
        break;
      case 'info':
        return _getDoc(call.arguments as int);
      case 'page':
        return await _openPage(call.arguments);
      case 'render':
        return await _render(call.arguments);
      case 'releaseBuffer':
        return await _releaseBuffer(call.arguments);
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

  Future<dynamic> _render(dynamic args) async {
    return await _renderRaw(args, dontFlip: true, handleRawData: (src, width, height) {
      return {
        'addr': pinBufferByFakeAddress(src),
        'size': src.length,
        'width': width,
        'height': height,
      };
    });
  }

  Future<void> _releaseBuffer(dynamic args) async => unpinBufferByFakeAddress(args as int);

  Future<dynamic> _renderRaw(
    dynamic args, {
    required bool dontFlip,
    required FutureOr<dynamic> Function(Uint8List src, int width, int height) handleRawData,
  }) async {
    final docId = args['docId'] as int;
    final doc = _docs[docId];
    if (doc == null) return -3;
    final pageNumber = args['pageNumber'] as int;
    if (pageNumber < 1 || pageNumber > doc.numPages) return -6;
    final page = await js_util.promiseToFuture<PdfjsPage>(doc.getPage(pageNumber));

    final vp1 = page.getViewport(PdfjsViewportParams(scale: 1));
    final pw = vp1.width;
    //final ph = vp1.height;
    final fullWidth = args['fullWidth'] as double? ?? pw;
    //final fullHeight = args['fullHeight'] as double? ?? ph;
    final width = args['width'] as int?;
    final height = args['height'] as int?;
    final backgroundFill = args['backgroundFill'] as bool? ?? true;
    if (width == null || height == null || width <= 0 || height <= 0) return -7;

    final offsetX = -(args['srcX'] as int? ?? args['x'] as int? ?? 0).toDouble();
    final offsetY = -(args['srcY'] as int? ?? args['y'] as int? ?? 0).toDouble();

    final vp = page.getViewport(
        PdfjsViewportParams(scale: fullWidth / pw, offsetX: offsetX, offsetY: offsetY, dontFlip: dontFlip));

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
    return await handleRawData(src, width, height);
  }

  Future<int> _updateTex(dynamic args) async {
    return await _renderRaw(
      args,
      dontFlip: false,
      handleRawData: (src, width, height) {
        final id = args['texId'] as int;
        final destX = args['destX'] as int? ?? 0;
        final destY = args['destY'] as int? ?? 0;
        final data = _updateTexSize(id, args['texWidth'] as int, args['texHeight'] as int);
        final destStride = data.stride;
        final bpl = width * 4;
        int dp = data.getOffset(destX, destY);

        final shouldEnableNewBehavior = PdfTexture.shouldEnableNewBehavior;
        int sp = shouldEnableNewBehavior ? 0 : bpl * (height - 1);
        final srcStride = shouldEnableNewBehavior ? bpl : -bpl;

        for (int y = 0; y < height; y++) {
          for (int i = 0; i < bpl; i++) {
            data.data[dp + i] = src[sp + i];
          }
          dp += destStride;
          sp += srcStride;
        }

        _eventStreamController.sink.add(id);
        return 0;
      },
    );
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

  const RgbaData(this.id, this.width, this.height, this.data);

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
