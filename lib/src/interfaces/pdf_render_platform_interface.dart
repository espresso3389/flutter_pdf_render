import 'dart:async';
import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'pdf_render.dart';
import '../pdf_render_method_channel.dart';

/// Abstraction layer to isolate [PdfDocument]/[PdfPageImageTexture] implementation from the public interface.
abstract class PdfRenderPlatform extends PlatformInterface {
  /// Constructs a PdfRenderPlatform.
  PdfRenderPlatform() : super(token: _token);

  static final Object _token = Object();

  static PdfRenderPlatform _instance = PdfRenderPlatformMethodChannel();

  /// The default instance of [PdfRenderPlatform] to use.
  ///
  /// Defaults to [MethodChannelUrlLauncher].
  static PdfRenderPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [PdfRenderPlatform] when they register themselves.
  static set instance(PdfRenderPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Opening the specified file.
  Future<PdfDocument> openFile(String filePath);

  /// Opening the specified asset.
  Future<PdfDocument> openAsset(String name);

  /// Opening the PDF on memory.
  Future<PdfDocument> openData(Uint8List data);

  /// Create a new Flutter [Texture]. The object should be released by calling [dispose] method after use it.
  Future<PdfPageImageTexture> createTexture(
      {required FutureOr<PdfDocument> pdfDocument, required int pageNumber});
}
