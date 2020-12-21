

import 'dart:async';

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import '../wrappers/html.dart' as html;
import '../wrappers/js_util.dart' as js_util;

import 'pdf.js.dart';

class PdfRenderWebPlugin {
  static void registerWith(Registrar registrar) {
    final channel = MethodChannel(
      'pdf_render',
      const StandardMethodCodec(),
      registrar
    );
    final plugin = PdfRenderWebPlugin._();
    // final script = html.ScriptElement()
    //   ..type = "text/javascript"
    //   ..charset = "utf-8"
    //   ..async = true
    //   ..src = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@2.5.207/build/pdf.min.js';
    // html.querySelector('head')!.children.add(script);
    // script.onLoad.listen((event) {
    //   print('loaded!');
    //   Timer.periodic(Duration(milliseconds: 100), (timer) {
    //     final p = js.context['pdfjs-dist/build/pdf'];
    //     if (p is PdfJs) {
    //       plugin.comp.complete(p);
    //       timer.cancel();
    //       print('pdfjsLib loaded.');
    //       return;
    //     }
    //     print('pdfjsLib loading...: $p');
    //   });
    // });
    channel.setMethodCallHandler(plugin.handleMethodCall);
  }

  PdfRenderWebPlugin._() {
    _eventChannel.setController(_eventStreamController);
  }
  final _eventStreamController = StreamController<int>();
  final _eventChannel = PluginEventChannel('jp.espresso3389.pdf_render/web_texture_events');
  final _docs = Map<int, PdfjsDocument>();
  int _lastDocId = -1;
  final _textures = Map<int, html.CanvasElement>();
  int _texId = -1;

  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch(call.method) {
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
      'allowsCopying': true,
      'allowPrinting': true
    };
  }

  dynamic _openPage(dynamic args) async {
    final docId = args['docId'] as int;
    final doc = _docs[docId]!;
    final pageNumber = args['pageNumber'] as int;
    if (pageNumber < 1 || pageNumber > doc.numPages) return null;
    final page = await js_util.promiseToFuture<PdfjsPage>(doc.getPage(pageNumber));
    return {
      'docId': docId,
      'pageNumber': pageNumber,
      'width': page.view[2] - page.view[0],
      'height': page.view[3] - page.view[1],
    };
  }

  int _allocTex() {
    final canvas = html.document.createElement('canvas') as html.CanvasElement;
    _textures[++_texId] = canvas;
    js_util.setProperty(html.window, 'pdf_render_texture_$_texId', canvas);
    return _texId;
  }

  void _releaseTex(int id) {
    _textures.remove(id);
    js_util.setProperty(html.window, 'pdf_render_texture_$_texId', null);
  }

  int _resizeTex(dynamic args) {
    final id = args['texId'] as int;
    final canvas = _textures[id];
    if (canvas == null) return -1;
    final width = args['width'] as int;
    final height = args['height'] as int;
    canvas.width = width;
    canvas.height = height;

    _eventStreamController.sink.add(id);
    return 0;
  }

  Future<int> _updateTex(dynamic args) async {
    final id = args['texId'] as int;
    final canvas = _textures[id];
    if (canvas == null) return -1;
    final docId = args['docId'] as int;
    final doc = _docs[docId];
    if (doc == null) return -3;
    final pageNumber = args['pageNumber'] as int;
    if (pageNumber < 1 || pageNumber > doc.numPages)
      return -6;
    final page = await js_util.promiseToFuture<PdfjsPage>(doc.getPage(pageNumber));
    final vp = page.getViewport({'scale': 1.0});

    final fullWidth = args['fullWidth'] as double? ?? vp.width.toDouble();
    final fullHeight = args['fullHeight'] as double? ?? vp.height.toDouble();
    // FIXME: destX, destY not used yet
    // final destX = args['destX'] as int? ?? 0;
    // final destY = args['destY'] as int? ?? 0;
    final width = args['width'] as int? ?? 0;
    final height = args['height'] as int? ?? 0;
    final srcX = args['srcX'] as int? ?? 0;
    final srcY = args['srcY'] as int? ?? 0;
    final backgroundFill = args['backgroundFill'] as bool? ?? true;
    if (width <= 0 || height <= 0)
      return -7;

    final texWidth = args['texWidth'] as int?;
    final texHeight = args['texHeight'] as int?;
    if (texWidth != null && texHeight != null) {
      canvas.width = texWidth;
      canvas.height = texHeight;
    }

    vp.width = canvas.width!;
    vp.height = canvas.height!;
    vp.transform = [fullWidth / vp.width, 0, -srcX, 0, fullHeight / vp.height, -srcY];

    if (backgroundFill) {
      canvas.context2D.fillStyle = 'white';
      canvas.context2D.fillRect(0, 0, canvas.width!, canvas.height!);
    }

    page.render(PdfjsRenderContext(
      canvasContext: canvas.context2D,
      viewport: vp
    ));

    _eventStreamController.sink.add(id);
    return 0;
  }
}
