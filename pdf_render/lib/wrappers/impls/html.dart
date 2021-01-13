// Dummy implementation for artifacts defined in dart:html.

import 'dart:typed_data';

abstract class CanvasElement {
  CanvasRenderingContext2D get context2D;
  int? get width;
  set width(int? width);
  int? get height;
  set height(int? height);
}
abstract class CanvasRenderingContext2D {
  ImageData getImageData(int x, int y, int w, int h);
  String get fillStyle;
  set fillStyle(String fillStyle);
  void fillRect(int x, int y, int w, int h);
}
abstract class ImageData {
  Uint8ClampedList get data;
  int get height;
  int get width;
}

final window = {};

class HtmlDocument {
  HtmlDocument._();
  Object createElement(String name) => throw UnimplementedError();
}
final document = HtmlDocument._();
