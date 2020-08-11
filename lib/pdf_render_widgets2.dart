import 'dart:async';
import 'dart:io';
import 'dart:math';
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
/// The second paramter [pageSize] is the original page size in pt.
/// You can determine the final page size shown in the flutter UI using the size
/// and then pass the size to [textureBuilder] function on the third parameter,
/// which generates the final [Widget].
typedef PdfPageBuilder = Widget Function(
    BuildContext context, PdfPageTextureBuilder textureBuilder, Size pageSize);

/// Function definition to generate the actual widget that contains rendered PDF page image.
/// [size] should be the page widget size but it can be null if you don't want to calculate it.
/// Unlike the function name, it may generate widget other than [Texture].
/// If [returnNullForError] is true, the function returns null if rendering failure; otherwise,
/// the function generates a placeholder [Container] for the unavailable page image.
/// Anyway, please note that the size is in screen coordinates; not the actual pixel size of
/// the image. In other words, the function correctly deals with the screen pixel density automatically.
/// [backgroundFill] specifies whether to fill background before rendering actual page content or not.
/// The page content may not have background fill and if the flag is false, it may be rendered with transparent background.
/// [renderingPixelRatio] specifies pixel density for rendering page image. If it is null, the value is obtained by calling `MediaQuery.of(context).devicePixelRatio`.
/// Although, the view uses Flutter's [Texture] to render the PDF content by default, you can disable it by setting [dontUseTexture] to true.
/// Please note that on iOS Simulator, it always use non-[Texture] rendering pass.
typedef PdfPageTextureBuilder = Widget Function({
  Size size,
  bool returnNullForError,
  PdfPagePlaceholderBuilder placeholderBuilder,
  bool backgroundFill,
  double renderingPixelRatio,
  bool dontUseTexture
});

/// Creates page placeholder that is shown on page loading or even page load failure.
typedef PdfPagePlaceholderBuilder = Widget Function(Size size, PdfPageStatus status);

/// Page loading status.
enum PdfPageStatus {
  /// The page is currently being loaded.
  loading,
  /// The page load failed.
  loadFailed,
}

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
  /// If you want to show multiple pages in the widget tree, use [PdfPageView].
  final int pageNumber;

  /// Function to build page widget tree. It can be null if you don't want to render the page with the widget or use the default page builder.
  final PdfPageBuilder pageBuilder;

  /// Error callback
  final Function(dynamic) onError;

  /// For multiple pages, use [documentBuilder] with [PdfPageView].
  /// For single page use, you must specify [pageNumber] and, optionally [calculateSize].
  PdfDocumentLoader({
    Key key,
    this.filePath,
    this.assetName,
    this.data,
    this.documentBuilder,
    this.pageNumber,
    this.pageBuilder,
    this.onError,
  }) : super(key: key);

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
        pageNumber <= _cachedPageSizes.length) {
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
    try {
      if (widget.filePath != null) {
        _doc = await PdfDocument.openFile(widget.filePath);
      } else if (widget.assetName != null) {
        _doc = await PdfDocument.openAsset(widget.assetName);
      } else if (widget.data != null) {
        _doc = await PdfDocument.openData(widget.data);
      } else {
        _doc = null;
      }
    } catch (e) {
      _doc = null;
      widget.onError?.call(e);
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

  PdfPageView(
      {Key key,
      this.pdfDocument,
      @required this.pageNumber,
      this.pageBuilder})
      : super(key: key);

  @override
  _PdfPageViewState createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {

  /// The default size; A4 595x842 px.
  static const defaultSize = Size(595, 842);

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
    return pageBuilder(context, _textureBuilder, _pageSize);
  }

  Widget _pageBuilder(BuildContext context, PdfPageTextureBuilder textureBuilder, Size pageSize) {
    return LayoutBuilder(
        builder: (context, constraints) => textureBuilder());
  }

  Size get _pageSize => _size ?? defaultSize;

  Size _sizeFromConstratints(BoxConstraints constraints, Size pageSize) {
    final ratio = min(constraints.maxWidth / pageSize.width, constraints.maxHeight / pageSize.height);
    return Size(pageSize.width * ratio, pageSize.height * ratio);
  }

  Widget _textureBuilder({Size size, bool returnNullForError, PdfPagePlaceholderBuilder placeholderBuilder, bool backgroundFill, double renderingPixelRatio, bool dontUseTexture}) {
    return LayoutBuilder(builder: (context, constraints) {
      size ??= _sizeFromConstratints(constraints, _pageSize);
      placeholderBuilder ??= (size, status) => Container(width: size.width, height: size.height, color: Color.fromARGB(255, 220, 220, 220));
      return FutureBuilder<bool>(
          future: _buildTexture(size: size, backgroundFill: backgroundFill, renderingPixelRatio: renderingPixelRatio, dontUseTexture: dontUseTexture),
          initialData: false,
          builder: (context, snapshot) {
            if (snapshot.data != true) {
              // still loading
              return placeholderBuilder(size, PdfPageStatus.loading);
            }

            if (_texture?.texId == null && _image?.imageIfAvailable == null) {
              // some loading error
              return returnNullForError == true ? null : placeholderBuilder(size, PdfPageStatus.loadFailed);
            }

            Widget contentWidget = _texture?.texId != null
            ? SizedBox(
              width: size.width,
              height: size.height,
              child: Texture(textureId: _texture.texId))
            : RawImage(image: _image?.imageIfAvailable);

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

  Future<bool> _buildTexture({@required Size size, bool backgroundFill, double renderingPixelRatio, bool dontUseTexture}) async {
    if (_doc == null ||
        widget.pageNumber == null ||
        widget.pageNumber < 1 ||
        widget.pageNumber > _doc.pageCount ||
        _page == null) {
      return true;
    }

    if (_isIosSimulator == null) {
      _isIosSimulator = await _determineWhetherIOSSimulatorOrNot();
    }

    final pixelRatio = renderingPixelRatio ?? MediaQuery.of(context).devicePixelRatio;
    final pixelSize = size * pixelRatio;
    if (dontUseTexture == true || _isIosSimulator == true) {
      _image = await _page.render(
        width: pixelSize.width.toInt(),
        height: pixelSize.height.toInt(),
        fullWidth: pixelSize.width,
        fullHeight: pixelSize.height,
        backgroundFill: backgroundFill);
      await _image.createImageIfNotAvailable();
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
        backgroundFill: backgroundFill);
    }
    return true;
  }

  static Future<bool> _determineWhetherIOSSimulatorOrNot() async {
    if (!Platform.isIOS) {
      return false;
    }
    final info = await DeviceInfoPlugin().iosInfo;
    return !info.isPhysicalDevice;
  }
}

class PdfInteractiveViewer extends StatefulWidget {

  PdfDocument doc;
  double padding;

  PdfInteractiveViewer({this.doc, this.padding});

  @override
  _PdfInteractiveViewerState createState() => _PdfInteractiveViewerState();
}

class _PdfInteractiveViewerState extends State<PdfInteractiveViewer> {

  List<_PdfPageState> _pages;
  TransformationController _controller;
  BoxConstraints _lastConstraints;
  Timer _timer;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
    _controller.addListener(() {
      if (_lastConstraints != null) {
        update(_lastConstraints);
      }
    });
    load();
  }

  @override
  void didUpdateWidget(PdfInteractiveViewer oldWidget) {
    if (oldWidget.doc != widget.doc) {
      load();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _releasePages();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _lastConstraints = constraints;
        final docSize = relayout(constraints);
        return InteractiveViewer(
        transformationController: _controller,
        constrained: false,
        minScale: 0.1,
        maxScale: 20,
        child: Stack(
          children: <Widget>[
            SizedBox(width: docSize.width, height: docSize.height),

            ...iterateLaidOutPages(constraints)
          ],
        )
      );
      },
    );
  }

  Future<void> load() async {
    _releasePages();
    _pages = List<_PdfPageState>();
    final firstPage = await widget.doc.getPage(1);
    final pageSize1 = Size(firstPage.width, firstPage.height);
    for (int i = 0; i < widget.doc.pageCount; i++) {
      _pages.add(_PdfPageState._(pageNumber: i + 1, pageSize: pageSize1));
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _releasePages() {
    if (_pages == null) return;
    for (final p in _pages) {
      p.dispose();
    }
    _pages = null;
  }

  double get padding => widget.padding ?? 8.0;

  Size relayout(BoxConstraints constraints, {bool force = false}) {
    final maxWidth = _pages.fold<double>(0.0, (maxWidth, page) => max(maxWidth, page.pageSize.width));
    final ratio = (constraints.maxWidth - padding * 2) / maxWidth;
    var top = padding;
    for (int i = 0; i < _pages.length; i++) {
      final page = _pages[i];
      final w = page.pageSize.width * ratio;
      final h = page.pageSize.height * ratio;
      page.rect = Rect.fromLTWH(padding, top, w, h);
      top += h + padding;
    }
    update(constraints);
    return Size(constraints.maxWidth, top);
  }

  Iterable<Widget> iterateLaidOutPages(BoxConstraints constraints) sync* {
    if (_pages != null) {
      final m = _controller.value;
      final r = m.row0[0];
      final exposed = Rect.fromLTWH(-m.row0[3], -m.row1[3], constraints.maxWidth, constraints.maxHeight).inflate(padding);

      for (final page in _pages) {
        final pageRectZoomed = Rect.fromLTRB(page.rect.left * r, page.rect.top * r, page.rect.right * r, page.rect.bottom * r);
        final part = pageRectZoomed.intersect(exposed);
        page.isVisibleInsideView = !part.isEmpty;
        if (!page.isVisibleInsideView) continue;

        yield Positioned(
          left: page.rect.left,
          top: page.rect.top,
          width: page.rect.width,
          height: page.rect.height,
          child: Container(
            width: page.rect.width,
            height: page.rect.height,
            child: Stack(
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: page._previewNotifier,
                  builder: (context, value, child) => page.preview != null ? Texture(textureId: page.preview.texId) : Container()
                ),
                ValueListenableBuilder<int>(
                  valueListenable: page._realSizeNotifier,
                  builder: (context, value, child) => page.realSizeOverlayRect != null && page.realSize != null
                  ? Positioned(
                      left: page.realSizeOverlayRect.left,
                      top: page.realSizeOverlayRect.top,
                      width: page.realSizeOverlayRect.width,
                      height: page.realSizeOverlayRect.height,
                      child: Texture(textureId: page.realSize.texId)
                    )
                  : Container()
                ),
              ]
            ),
            decoration: BoxDecoration(
              color: Color.fromARGB(255, 0, 0, 250),
              boxShadow: [
                BoxShadow(
                    color: Colors.black45,
                    blurRadius: 4,
                    offset: Offset(2, 2))
              ]
            ),
          ),
        );
      }
    }
  }

  static final extraBufferAroundView = 400.0;

  void update(BoxConstraints constraints) {
    _timer?.cancel();
    _timer = null;
    final m = _controller.value;
    final r = m.row0[0];
    final exposed = Rect.fromLTWH(-m.row0[3], -m.row1[3], constraints.maxWidth, constraints.maxHeight).inflate(extraBufferAroundView);
    var pagesToUpdate = 0;
    var changeCount = 0;
    for (final page in _pages) {
      if (page.rect == null) {
        page.isVisibleInsideView = false;
        continue;
      }
      final pageRectZoomed = Rect.fromLTRB(page.rect.left * r, page.rect.top * r, page.rect.right * r, page.rect.bottom * r);
      final part = pageRectZoomed.intersect(exposed);
      if (page.isVisibleInsideView != !part.isEmpty) {
        page.isVisibleInsideView = !part.isEmpty;
        changeCount++;
        if (part.isEmpty) {
          page.releaseTextures();
          print('releasing page ${page.pageNumber} $pageRectZoomed of $exposed');
        } else {
          pagesToUpdate++;
        }
      }
    }

    if (changeCount > 0) {
      Future.delayed(Duration.zero, () => setState(() { }));
    }
    if (pagesToUpdate > 0) {
      Future.delayed(Duration.zero, () => updatePageState(constraints));
    } else {
      _timer = Timer(Duration(milliseconds: 100), () => updateRealSize(constraints));
    }
  }

  Future<void> updatePageState(BoxConstraints constraints) async {
    final m = _controller.value;
    final r = m.row0[0];
    final exposed = Rect.fromLTWH(-m.row0[3], -m.row1[3], constraints.maxWidth, constraints.maxHeight).inflate(extraBufferAroundView);
    for (final page in _pages) {
      final pageRectZoomed = Rect.fromLTRB(page.rect.left * r, page.rect.top * r, page.rect.right * r, page.rect.bottom * r);
      final part = pageRectZoomed.intersect(exposed);
      if (part.isEmpty) continue;

      if (page.status == _PdfPageLoadingStatus.notInited) {
        page.status = _PdfPageLoadingStatus.initializing;
        page.pdfPage = await widget.doc.getPage(page.pageNumber);
        final prevPageSize = page.pageSize;
        page.pageSize = Size(page.pdfPage.width, page.pdfPage.height);
        page.status = _PdfPageLoadingStatus.inited;
        if (prevPageSize != page.pageSize && mounted) {
          relayout(constraints, force: true);
          return;
        }
      }
      if (page.status == _PdfPageLoadingStatus.inited) {
        page.status = _PdfPageLoadingStatus.pageLoading;
        page.preview = await PdfPageImageTexture.create(pdfDocument: page.pdfPage.document, pageNumber: page.pageNumber);
        final w = page.pdfPage.width.toInt();
        final h = page.pdfPage.height.toInt();
        await page.preview.updateRect(
          width: w,
          height: h,
          texWidth: w,
          texHeight: h,
          fullWidth: page.pdfPage.width,
          fullHeight: page.pdfPage.height);
        page.status = _PdfPageLoadingStatus.pageLoaded;
        page.updatePreview();
      }
    }

    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: 100), () => updateRealSize(constraints));
  }

  Future<void> updateRealSize(BoxConstraints constraints) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final m = _controller.value;
    final r = m.row0[0];
    final exposed = Rect.fromLTWH(-m.row0[3], -m.row1[3], constraints.maxWidth, constraints.maxHeight);
    for (final page in _pages) {
      if (page.status != _PdfPageLoadingStatus.pageLoaded) continue;
      final pageRectZoomed = Rect.fromLTRB(page.rect.left * r, page.rect.top * r, page.rect.right * r, page.rect.bottom * r);
      final part = pageRectZoomed.intersect(exposed);
      if (part.isEmpty) continue;
      final fw = pageRectZoomed.width * dpr;
      final fh = pageRectZoomed.height * dpr;
      if (page.preview?.hasUpdatedTexture == true && fw <= page.preview.texWidth && fh <= page.preview.texHeight) {
        // no real-size overlay needed; use preview
        page.realSizeOverlayRect = null;
      } else {
        // render real-size overlay
        final offset = part.topLeft - pageRectZoomed.topLeft;
        page.realSizeOverlayRect = Rect.fromLTWH(offset.dx / r, offset.dy / r, part.width / r, part.height / r);
        page.realSize ??= await PdfPageImageTexture.create(pdfDocument: page.pdfPage.document, pageNumber: page.pageNumber);
        final w = (part.width * dpr).toInt();
        final h = (part.height * dpr).toInt();
        page.realSize.updateRect(
          width: w,
          height: h,
          srcX: (offset.dx * dpr).toInt(),
          srcY: (offset.dy * dpr).toInt(),
          texWidth: w,
          texHeight: h,
          fullWidth: fw,
          fullHeight: fh);
      }
      page.updateRealSize();
      print('Updating page ${page.pageNumber} ${part}');
    }
  }
}

enum _PdfPageLoadingStatus {
  notInited,
  initializing,
  inited,
  pageLoading,
  pageLoaded
}

class _PdfPageState {
  /// Page number (started at 1).
  final int pageNumber;

  /// Where the page is layed out if available.
  Rect rect;
  /// [PdfPage] corresponding to the page if available.
  PdfPage pdfPage;
  /// Size at 72-dpi. During the initialization, the size may be just a copy of the size of the first page.
  Size pageSize;
  /// Preview image of the page rendered at low resolution.
  PdfPageImageTexture preview;
  /// Relative position of the realSize overlay. null to not show realSize overlay.
  Rect realSizeOverlayRect;
  /// realSize overlay.
  PdfPageImageTexture realSize;

  bool isVisibleInsideView = false;

  _PdfPageLoadingStatus status = _PdfPageLoadingStatus.notInited;

  final _previewNotifier = ValueNotifier<int>(0);
  final _realSizeNotifier = ValueNotifier<int>(0);

  _PdfPageState._({@required this.pageNumber, @required this.pageSize});

  Widget previewTexture() => _textureFor(preview, _previewNotifier);
  void updatePreview() { _previewNotifier.value++; }

  Widget realSizeTexture() => _textureFor(realSize, _realSizeNotifier);
  void updateRealSize() { _realSizeNotifier.value++; }

  Widget _textureFor(PdfPageImageTexture t, ValueNotifier<int> n) {
    return ValueListenableBuilder<int>(
      valueListenable: n,
      builder: (context, value, child) => t != null ? Texture(textureId: t.texId) : Container(),
    );
  }

  void releaseTextures() {
    if (preview == null) return;
    preview.dispose();
    realSize?.dispose();
    preview = null;
    realSize = null;
    status = _PdfPageLoadingStatus.inited;
  }

  void dispose() {
    releaseTextures();
    _previewNotifier.dispose();
    _realSizeNotifier.dispose();
  }
}
