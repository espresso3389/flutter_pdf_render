import 'dart:typed_data';

/// Dummy Uint8 definition for Flutter Web
class Uint8 { }
/// Dummy Pointer definition for Flutter Web
class Pointer<T> {
  int get address => throw UnimplementedError();
  factory Pointer.fromAddress(int ptr) => throw UnimplementedError();
}

/// Dummy Pointer<Uint8> extension methods for Flutter Web
extension Uint8Pointer on Pointer<Uint8> {
  int get value => throw UnimplementedError();
  void set value(int value) => throw UnimplementedError();
  int operator [](int index) => throw UnimplementedError();
  void operator []=(int index, int value) => throw UnimplementedError();
  Uint8List asTypedList(int length) => throw UnimplementedError();
}
