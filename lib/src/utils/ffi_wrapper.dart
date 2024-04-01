// This file is used to switch dart:ffi import to dummy import for Flutter Web
export 'dart:ffi' if (dart.library.js) 'web_pointer.dart';
