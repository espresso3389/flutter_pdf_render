import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

/// [Uint8] is not defined for Flutter Web. This is just a dummy definition.
class Uint8 {}

/// Works only for [Uint8];
class Pointer<T> {
  final int _address;
  Pointer._(this._address);
  factory Pointer.fromAddress(int address) => Pointer._(address);

  int get address => _address;
  Uint8List get buffer => getBufferByFakeAddress(address);
}

/// Get buffer for Pointer<Uint8>.
extension Uint8Pointer on Pointer<Uint8> {
  Uint8List asTypedList(int length) => buffer;
}

int _fakeAddress = 0;

/// Associate an address with the specified buffer and return the address.
int pinBufferByFakeAddress(Uint8List buffer) {
  js_util.setProperty(html.window, 'pdf_render_buffer_$_fakeAddress', buffer);
  return _fakeAddress++;
}

/// Get the associated buffer for the address.
Uint8List getBufferByFakeAddress(int address) {
  return js_util.getProperty(html.window, 'pdf_render_buffer_$address')
      as Uint8List;
}

/// Release the associated buffer for the address.
void unpinBufferByFakeAddress(int address) {
  js_util.setProperty(html.window, 'pdf_render_buffer_$address', null);
}
