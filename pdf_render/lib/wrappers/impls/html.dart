import 'dart:typed_data';

abstract class CanvasElement {
  CanvasContext2D get context2D;
  int? get width;
  set width(int? width);
  int? get height;
  set height(int? height);
}
abstract class CanvasContext2D {
  CanvasImageData getImageData(int x, int y, int w, int h);
  String get fillStyle;
  set fillStyle(String fillStyle);
  void fillRect(int x, int y, int w, int h);
}
abstract class CanvasImageData {
  Uint8ClampedList get data;
}

Object window = {};

class HtmlDocument {
  HtmlDocument._();
  Object createElement(String name) => throw UnimplementedError();
}
HtmlDocument document = HtmlDocument._();
