import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info/device_info.dart';
import 'package:flutter/material.dart';
import 'pdf_render.dart';

/// Function definition to build widget tree for a PDF document.
/// [pdfDocument] is the PDF document and it is valid until the corresponding
/// [PdfDocumentLoader] is in the widget tree.
/// [pageCount] indicates the number of pages in it.
typedef Widget PdfDocumentBuilder(
    BuildContext context, PdfDocument pdfDocument, int pageCount);

/// Function definition to build widget tree corresponding to a PDF page; normally to decorate the rendered
/// PDF page with certain border and/or shadow and sometimes add page number on it.
/// [aspectRatio] is the aspect ratio of the PDF page (width / height). You can calculate the actual PDF page sized to passed to [textureBuilder].
/// [textureBuilder] will generate the actual widget that contains rendered PDF page image.
typedef PdfPageBuilder = Widget Function(BuildContext context,
    double aspectRatio, PdfPageTextureBuilder textureBuilder);

/// Function definition to generate the actual widget that contains rendered PDF page image.
/// [size] should be the page widget size but it can be null if you don't want to calculate it.
typedef PdfPageTextureBuilder = Widget Function(Size size);

class PdfDocumentLoader extends StatefulWidget {
  // only one of [filePath], [assetName], or [data] have to be specified.
  final String filePath;
  final String assetName;
  final Uint8List data;
  //final String password;
  /// Function to build widget tree corresponding to PDF document.
  final PdfDocumentBuilder documentBuilder;

  /// Page number of the page to render if only one page should be shown.
  /// Could not be used with [documentBuilder].
  final int pageNumber;

  /// Whether to fill background before rendering actual page content or not.
  /// The page content may not have background fill and if the flag is false, it may be rendered with transparent background.
  /// Could not be used with [documentBuilder].
  final bool backgroundFill;

  /// Pixel density for rendering page image. If it is null, the value is obtained by calling `MediaQuery.of(context).devicePixelRatio`.
  /// Could not be used with [documentBuilder].
  final double renderingPixelRatio;

  /// Function to build page widget tree. It can be null if you don't want to render the page with the widget or use the default page builder.
  final PdfPageBuilder pageBuilder;

  /// For multiple pages, use [documentBuilder] with [PdfPageView].
  /// For single page use, you must specify [pageNumber] and, optionally [calculateSize].
  PdfDocumentLoader(
      {Key key,
      this.filePath,
      this.assetName,
      this.data,
      this.documentBuilder,
      this.pageNumber,
      this.backgroundFill = true,
      this.renderingPixelRatio,
      this.pageBuilder})
      : super(key: key);

  @override
  _PdfDocumentLoaderState createState() => _PdfDocumentLoaderState();
}

class _PdfDocumentLoaderState extends State<PdfDocumentLoader> {
  PdfDocument _doc;

  /// _lastPageSize is important to keep consistency on unform page size on
  /// a PDF document.
  Size _lastPageSize;
  List<Size> _cachedPageSizes;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _setPageSize(int pageNumber, Size size) {
    _lastPageSize = size;
    if (pageNumber > 0 && pageNumber <= _doc.pageCount) {
      if (_cachedPageSizes == null)
        _cachedPageSizes = List<Size>(_doc.pageCount);
      _cachedPageSizes[pageNumber - 1] = size;
    }
  }

  Size _getPageSize(int pageNumber) {
    Size size;
    if (_cachedPageSizes != null &&
        pageNumber > 0 &&
        pageNumber <= _doc.pageCount) {
      size = _cachedPageSizes[pageNumber - 1];
    }
    size ??= _lastPageSize;
    return size;
  }

  @override
  void didUpdateWidget(PdfDocumentLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.assetName != widget.assetName ||
        oldWidget.data != widget.data) {
      _release();
      _init();
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  Future<void> _init() async {
    if (widget.filePath != null) {
      _doc = await PdfDocument.openFile(widget.filePath);
    } else if (widget.assetName != null) {
      _doc = await PdfDocument.openAsset(widget.assetName);
    } else if (widget.data != null) {
      _doc = await PdfDocument.openData(widget.data);
    } else {
      _doc = null;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _release() {
    _doc?.dispose();
    _doc = null;
  }

  @override
  Widget build(BuildContext context) {
    return widget.pageNumber != null
        ? PdfPageView(
            pdfDocument: _doc,
            pageNumber: widget.pageNumber,
            backgroundFill: widget.backgroundFill,
            renderingPixelRatio: widget.renderingPixelRatio,
            pageBuilder: widget.pageBuilder,
          )
        : widget.documentBuilder != null
            ? widget.documentBuilder(context, _doc, _doc?.pageCount ?? 0)
            : Container();
  }
}

/// Widget to render a page of PDF document. Normally used in combination with [PdfDocumentLoader].
class PdfPageView extends StatefulWidget {
  /// [PdfDocument] to render. If it is null, the actual document is obtained by locating ansestor [PdfDocumentLoader] widget.
  final PdfDocument pdfDocument;

  /// Page number of the page to render if only one page should be shown.
  final int pageNumber;

  /// Function to build page widget tree. It can be null if you want to use the default page builder.
  final PdfPageBuilder pageBuilder;

  /// Whether to fill background before rendering actual page content or not.
  /// The page content may not have background fill and if the flag is false, it may be rendered with transparent background.
  final bool backgroundFill;

  /// Pixel density for rendering page image. If it is null, the value is obtained by calling `MediaQuery.of(context).devicePixelRatio`.
  final double renderingPixelRatio;

  /// Although, the view uses Flutter's [Texture] to render the PDF content by default, you can disable it by setting the value to true.
  /// Please note that on iOS Simulator, it always use non-[Texture] rendering pass.
  final bool dontUseTexture;

  PdfPageView(
      {Key key,
      this.pdfDocument,
      @required this.pageNumber,
      this.pageBuilder,
      this.backgroundFill = true,
      this.renderingPixelRatio,
      this.dontUseTexture})
      : super(key: key);

  @override
  _PdfPageViewState createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {
  PdfDocument _doc;
  PdfPage _page;
  Size _size;
  PdfPageImageTexture _texture;
  PdfPageImage _image;
  bool _isIosSimulator;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(PdfPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfDocument != widget.pdfDocument ||
        oldWidget.pageNumber != widget.pageNumber ||
        oldWidget.backgroundFill != widget.backgroundFill ||
        oldWidget.pageBuilder != widget.pageBuilder) {
      _release();
      _init();
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  Future<void> _init() async {
    final docLoaderState = _getPdfDocumentLoaderState();
    _size = docLoaderState?._getPageSize(widget.pageNumber);
    _doc = widget.pdfDocument ?? docLoaderState?._doc;
    if (_doc == null) {
      _page = null;
    } else {
      _page = await _doc.getPage(widget.pageNumber);
      if (_page == null) {
        _release();
        _size = docLoaderState?._getPageSize(widget.pageNumber);
      } else {
        _size = Size(_page.width, _page.height);
        if (docLoaderState != null)
          docLoaderState?._setPageSize(widget.pageNumber, _size);
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  _PdfDocumentLoaderState _getPdfDocumentLoaderState() =>
      context?.findAncestorStateOfType<_PdfDocumentLoaderState>();

  void _release() {
    _doc = null;
    _page = null;
    _size = null;
    _texture?.dispose();
    _texture = null;
    _image?.dispose();
    _image = null;
  }

  @override
  Widget build(BuildContext context) {
    final pageBuilder = widget.pageBuilder ?? _pageBuilder;
    return pageBuilder(context, _aspectRatio, _textureBuilder);
  }

  Widget _pageBuilder(BuildContext context, double aspectRatio,
      PdfPageTextureBuilder textureBuilder) {
    return LayoutBuilder(
        builder: (context, constraints) =>
            _textureBuilder(_sizeFromConstratints(constraints, aspectRatio)));
  }

  double get _aspectRatio => _size != null ? _size.width / _size.height : 4 / 3;

  Size _sizeFromConstratints(BoxConstraints constraints, double aspectRatio) {
    if (constraints.maxWidth / aspectRatio < constraints.maxHeight) {
      return Size(constraints.maxWidth, constraints.maxWidth / aspectRatio);
    } else {
      return Size(constraints.maxHeight * aspectRatio, constraints.maxHeight);
    }
  }

  Widget _textureBuilder(Size size) {
    return LayoutBuilder(builder: (context, constraints) {
      size ??= _sizeFromConstratints(constraints, _aspectRatio);
      return FutureBuilder<bool>(
          future: _buildTexture(size),
          initialData: false,
          builder: (context, snapshot) {
            if (snapshot.data != true) {
              return Container(width: size.width, height: size.height);
            }

            Widget contentWidget = _texture != null
                ? Texture(textureId: _texture.texId)
                : _image?.image != null ? RawImage(image: _image.image) : null;

            contentWidget = Container(
                width: size.width,
                height: size.height,
                child: AspectRatio(
                    aspectRatio: _aspectRatio, child: contentWidget));

            if (_isIosSimulator == true) {
              contentWidget = Stack(
                children: <Widget>[
                  contentWidget,
                  const Text(
                      'Warning: on iOS Simulator, pdf_render work differently to physical device.',
                      style: TextStyle(color: Colors.redAccent))
                ],
              );
            }
            return contentWidget;
          });
    });
  }

  Future<bool> _buildTexture(Size size) async {
    if (_doc == null ||
        widget.pageNumber == null ||
        widget.pageNumber < 1 ||
        widget.pageNumber > _doc.pageCount) {
      return true;
    }

    if (_isIosSimulator == null) {
      _isIosSimulator = await _determineWhetherIOSSimulatorOrNot();
    }

    final pixelRatio =
        widget.renderingPixelRatio ?? MediaQuery.of(context).devicePixelRatio;
    final pixelSize = size * pixelRatio;
    if (widget.dontUseTexture == true || _isIosSimulator == true) {
      _image = await _page.render(
          width: pixelSize.width.toInt(),
          height: pixelSize.height.toInt(),
          fullWidth: pixelSize.width,
          fullHeight: pixelSize.height,
          backgroundFill: widget.backgroundFill);
    } else {
      if (_texture == null ||
          _texture.pdfDocument.docId != _doc.docId ||
          _texture.pageNumber != widget.pageNumber) {
        _image?.dispose();
        _image = null;
        _texture?.dispose();
        _texture = await PdfPageImageTexture.create(
            pdfDocument: _doc, pageNumber: widget.pageNumber);
      }
      await _texture.updateRect(
          width: pixelSize.width.toInt(),
          height: pixelSize.height.toInt(),
          texWidth: pixelSize.width.toInt(),
          texHeight: pixelSize.height.toInt(),
          fullWidth: pixelSize.width,
          fullHeight: pixelSize.height,
          backgroundFill: widget.backgroundFill);
    }
    return true;
  }

  Widget _buildPage() {
    if (_doc == null ||
        widget.pageNumber == null ||
        widget.pageNumber < 1 ||
        widget.pageNumber > _doc.pageCount ||
        _page == null ||
        (_texture == null && _image == null)) {
      return Container(width: _size?.width, height: _size?.height);
    }

    Widget contentWidget = _texture != null
        ? Texture(textureId: _texture.texId)
        : RawImage(image: _image.image);

    contentWidget = Container(
        width: _size.width,
        height: _size.height,
        color: Colors.black,
        child: contentWidget);

    if (_isIosSimulator) {
      contentWidget = Stack(
        children: <Widget>[
          contentWidget,
          const Text(
              'Warning: on iOS Simulator, pdf_render work differently to physical device.',
              style: TextStyle(color: Colors.redAccent))
        ],
      );
    }

    return contentWidget;
  }

  static Future<bool> _determineWhetherIOSSimulatorOrNot() async {
    if (!Platform.isIOS) {
      return false;
    }
    final info = await DeviceInfoPlugin().iosInfo;
    return !info.isPhysicalDevice;
  }
}
