import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../html.dart' as html;
import '../js_util.dart' as js_util;

class PdfTexture extends StatefulWidget {
  final int textureId;
  const PdfTexture({required this.textureId, Key? key}) : super(key: key);
  @override
  PdfTextureState createState() => PdfTextureState();

  ui.Image? get texture =>
      js_util.getProperty(html.window, 'pdf_render_texture_$textureId')
          as ui.Image?;
}

class PdfTextureState extends State<PdfTexture> {
  @override
  void initState() {
    super.initState();
    _WebTextureManager.instance.register(widget.textureId, this);
  }

  @override
  void dispose() {
    _WebTextureManager.instance.unregister(widget.textureId, this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PdfTexture oldWidget) {
    if (oldWidget.textureId != widget.textureId) {
      _WebTextureManager.instance.unregister(oldWidget.textureId, this);
      _WebTextureManager.instance.register(widget.textureId, this);
      _requestUpdate();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return RawImage(
      image: widget.texture,
      alignment: Alignment.topLeft,
      fit: BoxFit.fill,
    );
  }

  void _requestUpdate() {
    if (mounted) setState(() {});
  }
}

/// Receiving WebTexture update event from JS side.
class _WebTextureManager {
  static final instance = _WebTextureManager._();

  final _id2states = <int, List<PdfTextureState>>{};
  final _events =
      const EventChannel('jp.espresso3389.pdf_render/web_texture_events');

  _WebTextureManager._() {
    _events.receiveBroadcastStream().listen((event) {
      if (event is int) {
        notify(event);
      }
    });
  }

  void register(int id, PdfTextureState state) =>
      _id2states.putIfAbsent(id, () => []).add(state);

  void unregister(int id, PdfTextureState state) {
    final states = _id2states[id];
    if (states != null) {
      if (states.remove(state)) {
        if (states.isEmpty) {
          _id2states.remove(id);
        }
      }
    }
  }

  void notify(int id) {
    final list = _id2states[id];
    if (list != null) {
      for (final s in list) {
        s._requestUpdate();
      }
    }
  }
}
