@JS()
library pdf.js;

import 'dart:js_util';
import 'dart:typed_data';

import 'package:js/js.dart';

import '../wrappers/html.dart';

@JS('pdfjsLib.getDocument')
external _PDFDocumentLoadingTask _pdfjsGetDocument(dynamic data);

@JS('pdfRenderOptions')
external Object _pdfRenderOptions;

@JS()
@anonymous
class _PDFDocumentLoadingTask {
  external Object get promise;
}

Map<String, dynamic> _getParams(Map<String, dynamic> jsParams) {
  final params = {
    'cMapUrl': getProperty(_pdfRenderOptions, 'cMapUrl'),
    'cMapPacked': getProperty(_pdfRenderOptions, 'cMapPacked'),
  }..addAll(jsParams);
  final otherParams = getProperty(_pdfRenderOptions, 'params');
  if (otherParams != null) {
    params.addAll(otherParams);
  }
  return params;
}

Future<PdfjsDocument> _pdfjsGetDocumentJsParams(Map<String, dynamic> jsParams) {
  return promiseToFuture<PdfjsDocument>(
      _pdfjsGetDocument(jsify(_getParams(jsParams))).promise);
}

Future<PdfjsDocument> pdfjsGetDocument(String url) =>
    _pdfjsGetDocumentJsParams({'url': url});

Future<PdfjsDocument> pdfjsGetDocumentFromData(ByteBuffer data) =>
    _pdfjsGetDocumentJsParams({'data': data});

@JS()
@anonymous
class PdfjsDocument {
  external Object getPage(int pageNumber);
  external int get numPages;
  external void destroy();
}

@JS()
@anonymous
class PdfjsPage {
  external PdfjsViewport getViewport(PdfjsViewportParams params);

  /// `viewport` for [PdfjsViewport] and `transform` for
  external PdfjsRender render(PdfjsRenderContext params);
  external int get pageNumber;
  external List<double> get view;
}

@JS()
@anonymous
class PdfjsViewportParams {
  external double get scale;
  external set scale(double scale);
  external int get rotation;
  external set rotation(int rotation);
  external double get offsetX;
  external set offsetX(double offsetX);
  external double get offsetY;
  external set offsetY(double offsetY);
  external bool get dontFlip;
  external set dontFlip(bool dontFlip);

  external factory PdfjsViewportParams(
      {double scale,
      int rotation, // 0, 90, 180, 270
      double offsetX = 0,
      double offsetY = 0,
      bool dontFlip = false});
}

@JS('PageViewport')
class PdfjsViewport {
  external List<double> get viewBox;
  external set viewBox(List<double> viewBox);

  external double get scale;
  external set scale(double scale);

  /// 0, 90, 180, 270
  external int get rotation;
  external set rotation(int rotation);
  external double get offsetX;
  external set offsetX(double offsetX);
  external double get offsetY;
  external set offsetY(double offsetY);
  external bool get dontFlip;
  external set dontFlip(bool dontFlip);

  external double get width;
  external set width(double w);
  external double get height;
  external set height(double h);

  external List<double>? get transform;
  external set transform(List<double>? m);
}

@JS()
@anonymous
class PdfjsRenderContext {
  external CanvasRenderingContext2D get canvasContext;
  external set canvasContext(CanvasRenderingContext2D ctx);
  external PdfjsViewport get viewport;
  external set viewport(PdfjsViewport viewport);
  external String get intent;

  /// `display` or `print`
  external set intent(String intent);
  external bool get renderInteractiveForms;
  external set renderInteractiveForms(bool renderInteractiveForms);
  external List<int>? get transform;
  external set transform(List<int>? transform);
  external dynamic get imageLayer;
  external set imageLayer(dynamic imageLayer);
  external dynamic get canvasFactory;
  external set canvasFactory(dynamic canvasFactory);
  external dynamic get background;
  external set background(dynamic background);
  external factory PdfjsRenderContext(
      {required CanvasRenderingContext2D canvasContext,
      required PdfjsViewport viewport,
      String intent = 'display',
      bool renderInteractiveForms = false,
      List<double>? transform,
      dynamic imageLayer,
      dynamic canvasFactory,
      dynamic background});
}

@anonymous
@JS()
class PdfjsRender {
  external Future<void> get promise;
}
