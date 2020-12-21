import 'package:flutter/widgets.dart';

class PdfTexture extends StatelessWidget {
  final int textureId;
  PdfTexture({required this.textureId, Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Texture(textureId: textureId);
  }
}
