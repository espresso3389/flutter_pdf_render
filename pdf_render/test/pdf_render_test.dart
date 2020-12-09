import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
//import 'package:pdf_render/pdf_render.dart';

void main() {
  const MethodChannel channel = MethodChannel('pdf_render');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    //expect(await PdfRender.platformVersion, '42');
  });
}
