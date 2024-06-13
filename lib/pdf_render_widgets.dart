import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as math64;

import 'pdf_render.dart';
import 'src/wrappers/pdf_texture.dart';
import 'src/interfaces/interactive_viewer.dart' as iv;

/// Function definition to build widget tree for a PDF document.
///
/// [pdfDocument] is the PDF document and it is valid until the corresponding
/// [PdfDocumentLoader] is in the widget tree. It may be null.
/// [pageCount] indicates the number of pages in it.
typedef PdfDocumentBuilder = Widget Function(
    BuildContext context, PdfDocument? pdfDocument, int pageCount);

/// Function definition to build widget tree corresponding to a PDF page.
///
/// The function used to decorate the rendered PDF page with certain border and/or shadow
/// and sometimes add page number on it.
/// The second parameter [pageSize] is the original page size in pt.
/// You can determine the final page size shown in the flutter UI using the size
/// and then pass the size to [textureBuilder] function on the third parameter,
/// which generates the final [Widget].
typedef PdfPageBuilder = Widget Function(
    BuildContext context, PdfPageTextureBuilder textureBuilder, Size pageSize);

/// Function definition to generate the actual widget that contains rendered PDF page image.
///
/// [size] should be the page widget size but it can be null if you don't want to calculate it.
/// Unlike the function name, it may generate widget other than [Texture].
/// the function generates a placeholder [Container] for the unavailable page image.
/// Anyway, please note that the size is in screen coordinates; not the actual pixel size of
/// the image. In other words, the function correctly deals with the screen pixel density automatically.
/// [backgroundFill] specifies whether to fill background before rendering actual page content or not.
/// The page content may not have background fill and if the flag is false, it may be rendered with transparent
/// background.
/// [allowAntialiasingIOS] specifies whether to allow use of antialiasing on iOS Quartz PDF rendering
/// [renderingPixelRatio] specifies pixel density for rendering page image. If it is null, the value is obtained by
/// calling `MediaQuery.of(context).devicePixelRatio`.
/// Please note that on iOS Simulator, it always use non-[Texture] rendering pass.
typedef PdfPageTextureBuilder = Widget Function(
    {Size? size,
    PdfPagePlaceholderBuilder? placeholderBuilder,
    bool backgroundFill,
    bool allowAntialiasingIOS,
    double? renderingPixelRatio});

/// Creates page placeholder that is shown on page loading or even page load failure.
typedef PdfPagePlaceholderBuilder = Widget Function(
    Size size, PdfPageStatus status);

/// Page loading status.
enum PdfPageStatus {
  /// The page is currently being loaded.
  loading,

  /// The page load failed.
  loadFailed,
}

/// Error handler.
typedef OnError = void Function(dynamic);

/// Exception-proof await/cache mechanism on [PdfDocument] Future.
class _PdfDocumentAwaiter {
  _PdfDocumentAwaiter(this._docFuture, {this.onError});

  final FutureOr<PdfDocument> _docFuture;
  final OnError? onError;
  PdfDocument? _cached;

  Future<PdfDocument?> getValue() async {
    if (_cached == null) {
      try {
        _cached = await _docFuture;
      } catch (e) {
        onError?.call(e);
      }
    }
    return _cached;
  }
}

/// [PdfDocumentLoader] is a [Widget] that used to load arbitrary PDF document and manages [PdfDocument] instance.
class PdfDocumentLoader extends StatefulWidget {
  final FutureOr<PdfDocument> doc;

  /// Function to build widget tree corresponding to PDF document.
  final PdfDocumentBuilder? documentBuilder;

  /// Page number of the page to render if only one page should be shown.
  ///
  /// Could not be used with [documentBuilder].
  /// If you want to show multiple pages in the widget tree, use [PdfPageView].
  final int? pageNumber;

  /// Function to build page widget tree.
  ///
  /// It can be null if you don't want to render the page with the widget or use the default page builder.
  final PdfPageBuilder? pageBuilder;

  /// Error callback
  final Function(dynamic)? onError;

  /// Load PDF document from file.
  ///
  /// For additional parameters, see [PdfDocumentLoader].
  factory PdfDocumentLoader.openFile(
    String filePath, {
    Key? key,
    PdfDocumentBuilder? documentBuilder,
    int? pageNumber,
    PdfPageBuilder? pageBuilder,
    Function(dynamic)? onError,
  }) =>
      PdfDocumentLoader(
        key: key,
        doc: PdfDocument.openFile(filePath),
        documentBuilder: documentBuilder,
        pageNumber: pageNumber,
        pageBuilder: pageBuilder,
        onError: onError,
      );

  /// Load PDF document from asset.
  ///
  /// For additional parameters, see [PdfDocumentLoader].
  factory PdfDocumentLoader.openAsset(
    String assetName, {
    Key? key,
    PdfDocumentBuilder? documentBuilder,
    int? pageNumber,
    PdfPageBuilder? pageBuilder,
    Function(dynamic)? onError,
  }) =>
      PdfDocumentLoader(
        key: key,
        doc: PdfDocument.openAsset(assetName),
        documentBuilder: documentBuilder,
        pageNumber: pageNumber,
        pageBuilder: pageBuilder,
        onError: onError,
      );

  /// Load PDF document from PDF binary data.
  ///
  /// For additional parameters, see [PdfDocumentLoader].
  factory PdfDocumentLoader.openData(
    Uint8List data, {
    Key? key,
    PdfDocumentBuilder? documentBuilder,
    int? pageNumber,
    PdfPageBuilder? pageBuilder,
    Function(dynamic)? onError,
  }) =>
      PdfDocumentLoader(
        key: key,
        doc: PdfDocument.openData(data),
        documentBuilder: documentBuilder,
        pageNumber: pageNumber,
        pageBuilder: pageBuilder,
        onError: onError,
      );

  /// Use one of [PdfDocumentLoader.openFile], [PdfDocumentLoader.openAsset],
  /// or [PdfDocumentLoader.openData] in normal case.
  /// If you already have [PdfDocument], you can use the method.
  PdfDocumentLoader({
    Key? key,
    required this.doc,
    this.documentBuilder,
    this.pageNumber,
    this.pageBuilder,
    this.onError,
  }) : super(key: key);

  @override
  PdfDocumentLoaderState createState() => PdfDocumentLoaderState();

  /// Error-safe wrapper on [doc].
  late final _docCache = _PdfDocumentAwaiter(doc, onError: onError);
}

class PdfDocumentLoaderState extends State<PdfDocumentLoader> {
  PdfDocument? _doc;

  /// _lastPageSize is important to keep consistency on uniform page size on
  /// a PDF document.
  Size? _lastPageSize;
  List<Size?>? _cachedPageSizes;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _setPageSize(int pageNumber, Size? size) {
    _lastPageSize = size;
    if (pageNumber > 0 && pageNumber <= _doc!.pageCount) {
      if (_cachedPageSizes == null ||
          _cachedPageSizes?.length != _doc!.pageCount) {
        _cachedPageSizes = List<Size?>.filled(_doc!.pageCount, null);
      }
      _cachedPageSizes![pageNumber - 1] = size;
    }
  }

  Size? _getPageSize(int? pageNumber) {
    Size? size;
    if (_cachedPageSizes != null &&
        pageNumber! > 0 &&
        pageNumber <= _cachedPageSizes!.length) {
      size = _cachedPageSizes![pageNumber - 1];
    }
    size ??= _lastPageSize;
    return size;
  }

  @override
  void didUpdateWidget(PdfDocumentLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateDoc();
  }

  Future<void> _updateDoc() async {
    final newDoc = await widget._docCache.getValue();
    if (newDoc != _doc) {
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
      _doc = await widget._docCache.getValue();
      if (_doc == null) {
        widget.onError?.call(ArgumentError('Cannot open the document'));
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
            ? widget.documentBuilder!(context, _doc, _doc?.pageCount ?? 0)
            : Container();
  }
}

/// Widget to render a page of PDF document. Normally used in combination with [PdfDocumentLoader].
class PdfPageView extends StatefulWidget {
  /// [PdfDocument] to render. If it is null, the actual document is obtained by locating ancestor [PdfDocumentLoader]
  /// widget.
  final PdfDocument? pdfDocument;

  /// Page number of the page to render if only one page should be shown.
  final int? pageNumber;

  /// Function to build page widget tree. It can be null if you want to use the default page builder.
  final PdfPageBuilder? pageBuilder;

  const PdfPageView(
      {Key? key, this.pdfDocument, required this.pageNumber, this.pageBuilder})
      : super(key: key);

  @override
  PdfPageViewState createState() => PdfPageViewState();
}

class PdfPageViewState extends State<PdfPageView> {
  /// The default size; A4 595x842 px.
  static const defaultSize = Size(595, 842);

  PdfDocument? _doc;
  PdfPage? _page;
  Size? _size;
  PdfPageImageTexture? _texture;

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
      try {
        _page = await _doc!.getPage(widget.pageNumber!);
      } catch (e) {
        _page = null;
      }
      if (_page == null) {
        _release();
        _size = docLoaderState?._getPageSize(widget.pageNumber);
      } else {
        _size = Size(_page!.width, _page!.height);
        if (docLoaderState != null) {
          docLoaderState._setPageSize(widget.pageNumber!, _size);
        }
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  PdfDocumentLoaderState? _getPdfDocumentLoaderState() =>
      context.findAncestorStateOfType<PdfDocumentLoaderState>();

  void _release() {
    _doc = null;
    _page = null;
    _size = null;
    _texture?.dispose();
    _texture = null;
  }

  @override
  Widget build(BuildContext context) {
    final pageBuilder = widget.pageBuilder ?? _pageBuilder;
    return pageBuilder(context, _textureBuilder, _pageSize);
  }

  Widget _pageBuilder(BuildContext context,
      PdfPageTextureBuilder textureBuilder, Size pageSize) {
    return LayoutBuilder(builder: (context, constraints) => textureBuilder());
  }

  Size get _pageSize => _size ?? defaultSize;

  Size _sizeFromConstraints(BoxConstraints constraints, Size pageSize) {
    final ratio = min(constraints.maxWidth / pageSize.width,
        constraints.maxHeight / pageSize.height);
    return Size(pageSize.width * ratio, pageSize.height * ratio);
  }

  Widget _textureBuilder({
    Size? size,
    PdfPagePlaceholderBuilder? placeholderBuilder,
    bool backgroundFill = true,
    bool allowAntialiasingIOS = true,
    double? renderingPixelRatio,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final finalSize = size ?? _sizeFromConstraints(constraints, _pageSize);
      final finalPlaceholderBuilder = placeholderBuilder ??
          (size, status) => Container(
              width: size.width,
              height: size.height,
              color: const Color.fromARGB(255, 220, 220, 220));
      return FutureBuilder<bool>(
          future: _buildTexture(
            size: finalSize,
            backgroundFill: backgroundFill,
            allowAntialiasingIOS: allowAntialiasingIOS,
            renderingPixelRatio: renderingPixelRatio,
          ),
          initialData: false,
          builder: (context, snapshot) {
            if (snapshot.data != true) {
              // still loading
              return finalPlaceholderBuilder(finalSize, PdfPageStatus.loading);
            }

            if (_texture?.texId == null) {
              // some loading error
              return finalPlaceholderBuilder(
                  finalSize, PdfPageStatus.loadFailed);
            }

            return SizedBox(
              width: finalSize.width,
              height: finalSize.height,
              child: PdfTexture(textureId: _texture!.texId),
            );
          });
    });
  }

  Future<bool> _buildTexture({
    required Size size,
    bool backgroundFill = true,
    bool allowAntialiasingIOS = true,
    double? renderingPixelRatio,
  }) async {
    if (_doc == null ||
        widget.pageNumber == null ||
        widget.pageNumber! < 1 ||
        widget.pageNumber! > _doc!.pageCount ||
        _page == null) {
      return true;
    }

    final pixelRatio =
        renderingPixelRatio ?? MediaQuery.of(context).devicePixelRatio;
    final pixelSize = size * pixelRatio;
    if (_texture == null ||
        _texture!.pdfDocument != _doc ||
        _texture!.pageNumber != widget.pageNumber) {
      _texture?.dispose();
      _texture = await PdfPageImageTexture.create(
          pdfDocument: _doc!, pageNumber: widget.pageNumber!);
    }
    await _texture!.extractSubrect(
      width: pixelSize.width.toInt(),
      height: pixelSize.height.toInt(),
      fullWidth: pixelSize.width,
      fullHeight: pixelSize.height,
      backgroundFill: backgroundFill,
      allowAntialiasingIOS: allowAntialiasingIOS,
    );

    return true;
  }
}

typedef LayoutPagesFunc = List<Rect> Function(
    Size contentViewSize, List<Size> pageSizes);
typedef BuildPageContentFunc = Widget Function(
    BuildContext context, int pageNumber, Rect pageRect);

/// Specifies where to anchor to.
enum PdfViewerAnchor {
  topLeft,
  top,
  topRight,
  left,
  center,
  right,
  bottomLeft,
  bottom,
  bottomRight,
}

/// Controller for [PdfViewer].
/// It is derived from [TransformationController] and basically compatible to [ValueNotifier<Matrix4>].
/// So you can pass it to [ValueListenableBuilder<Matrix4>] or such to receive any view status changes.
class PdfViewerController extends TransformationController {
  PdfViewerController();

  /// Associated [PdfViewerState].
  ///
  /// FIXME: I don't think this is a good structure for our purpose...
  PdfViewerState? _state;

  /// Associate a [PdfViewerState] to the controller.
  void _setViewerState(PdfViewerState? state) {
    _state = state;
    if (_state != null) notifyListeners();
  }

  /// Whether the controller is ready or not.
  ///
  /// If the controller is not ready, almost all methods on [PdfViewerController] won't work (throw some exception).
  /// For certain operations, it may be easier to use [ready] method to get [PdfViewerController?] not to execute
  /// methods unless it is ready.
  bool get isReady => _state?._pages != null;

  /// Helper method to return null when the controller is not ready([isReady]).
  ///
  /// It is useful if you want ot call methods like [goTo] with the property like the following fragment:
  /// ```dart
  /// controller.ready?.goToPage(pageNumber: 1);
  /// ```
  PdfViewerController? get ready => isReady ? this : null;

  /// Get total page count in the PDF document.
  ///
  /// If the controller is not ready([isReady]), the property throws some exception.
  int get pageCount => _state!._pages!.length;

  /// Get page location. If the page does not exist in the layout, it returns null.
  ///
  /// If the controller is not ready([isReady]), the property throws some exception.
  Rect? getPageRect(int pageNumber) => _state!._pages![pageNumber - 1].rect;

  /// Get the page.
  Future<PdfPage> getPage(int pageNumber) =>
      _state!._pages![pageNumber - 1].pdfPageCompleter.future;

  /// Get the [PdfViewer]'s view size.
  Size get viewSize => _state!._lastViewSize!;

  /// Get the full PDF content size in the [PdfViewer].
  Size get fullSize => _state!._docSize! * zoomRatio;

  /// Get the maximum scrollable offset in the [PdfViewer].
  Offset get scrollableMax =>
      Offset(getScrollableMaxX(zoomRatio), getScrollableMaxY(zoomRatio));

  /// Get the full PDF content size in the [PdfViewer] with the specified [zoomRatio].
  Size getFullSize(double zoomRatio) => _state!._docSize! * zoomRatio;

  /// Calculate maximum X that can be acceptable as a horizontal scroll position.
  double getScrollableMaxX(double zoomRatio) =>
      getFullSize(zoomRatio).width - _state!._lastViewSize!.width;

  /// Calculate maximum Y that can be acceptable as a vertical scroll position.
  double getScrollableMaxY(double zoomRatio) =>
      getFullSize(zoomRatio).height - _state!._lastViewSize!.height;

  /// Clamp horizontal scroll position into valid range.
  double clampX(double x, double zoomRatio) =>
      x.clamp(0.0, getScrollableMaxX(zoomRatio));

  /// Clamp vertical scroll position into valid range.
  double clampY(double y, double zoomRatio) =>
      y.clamp(0.0, getScrollableMaxY(zoomRatio));

  /// Calculate the matrix that corresponding to the page position.
  ///
  /// If the page does not exist in the layout, it returns null.
  /// If the controller is not ready([isReady]), the method throws some exception.
  Matrix4? calculatePageFitMatrix({required int pageNumber, double? padding}) =>
      calculatePageMatrix(
          pageNumber: pageNumber,
          padding: padding,
          x: 0,
          y: 0,
          anchor: PdfViewerAnchor.topLeft);

  /// Calculate the matrix that corresponding to the page of specified offset ([x], [y]) and specified [zoomRatio].
  ///
  /// [x],[y] should be in [0 1] range and they indicate relative position in the page:
  /// - 0 for top/left
  /// - 1 for bottom/right
  /// - 0.5 for center (the default)
  ///
  /// [anchor] specifies which widget corner, edge, or center the point specified by ([x],[y]) is anchored to.
  ///
  /// [zoomRatio] specifies the zoom ratio. The default is to use the zoom ratio that fit the page into the view.
  /// If you want to keep the current zoom ratio, use [PdfViewerController.zoomRatio] for the value.
  ///
  /// If the page does not exist in the layout, it returns null.
  /// If the controller is not ready([isReady]), the method throws some exception.
  Matrix4? calculatePageMatrix({
    required int pageNumber,
    double? padding,
    double x = 0.5,
    double y = 0.5,
    PdfViewerAnchor anchor = PdfViewerAnchor.center,
    double? zoomRatio,
  }) {
    final rect = getPageRect(pageNumber)?.inflate(padding ?? _state!._padding);
    if (rect == null) return null;
    final zoom1 = _state!._lastViewSize!.width / rect.width;
    final destZoom = zoomRatio ?? zoom1;
    final ratio = destZoom / zoom1;
    final viewWidth = _state!._lastViewSize!.width;
    final viewHeight = _state!._lastViewSize!.height;
    final left = clampX(
        (rect.left + rect.width * x) * ratio -
            viewWidth * (anchor.index % 3) / 2,
        destZoom);
    final top = clampY(
        (rect.top + rect.height * y) * ratio -
            viewHeight * (anchor.index ~/ 3) / 2,
        destZoom);

    return Matrix4.compose(
      math64.Vector3(-left, -top, 0),
      math64.Quaternion.identity(),
      math64.Vector3(destZoom, destZoom, 1),
    );
  }

  /// Go to the destination specified by the matrix.
  ///
  /// To go to a specific page, use [goToPage] method or use [calculatePageFitMatrix]/[calculatePageMatrix] method to calculate the page
  /// location matrix.
  /// If [destination] is null, the method does nothing.
  Future<void> goTo({
    Matrix4? destination,
    Duration duration = const Duration(milliseconds: 200),
  }) =>
      _state!._goTo(
        destination: destination,
        duration: duration,
      );

  /// Go to the specified page.
  Future<void> goToPage({
    required int pageNumber,
    double? padding,
    Duration duration = const Duration(milliseconds: 500),
  }) =>
      goTo(
        destination:
            calculatePageFitMatrix(pageNumber: pageNumber, padding: padding),
        duration: duration,
      );

  /// Go to specific point in page.
  ///
  /// [x],[y] should be in [0 1] range and they indicate relative position in the page:
  /// - 0 for top/left
  /// - 1 for bottom/right
  /// - 0.5 for center (the default)
  ///
  /// [anchor] specifies which widget corner, edge, or center the point specified by ([x],[y]) is anchored to.
  ///
  /// [zoomRatio] specifies the zoom ratio. The default is to use the zoom ratio that fit the page into the view.
  /// If you want to keep the current zoom ratio, use [PdfViewerController.zoomRatio] for the value.
  ///
  /// If the page does not exist in the layout, it returns null.
  /// If the controller is not ready([isReady]), the method throws some exception.
  Future<void> goToPointInPage({
    required int pageNumber,
    double? padding,
    double x = 0.5,
    double y = 0.5,
    PdfViewerAnchor anchor = PdfViewerAnchor.center,
    double? zoomRatio,
    Duration duration = const Duration(milliseconds: 500),
  }) =>
      goTo(
        destination: calculatePageMatrix(
          pageNumber: pageNumber,
          padding: padding,
          x: x,
          y: y,
          zoomRatio: zoomRatio,
          anchor: anchor,
        ),
        duration: duration,
      );

  /// Calculate the matrix that changes zoom ratio.
  ///
  /// [center] specifies the center of the zoom operation in widget's "local" coordinates. e.g. [TapDownDetails.localPosition]
  Matrix4 zoomMatrix(double zoomRatio, {Offset? center}) {
    final ratio = zoomRatio / this.zoomRatio;
    final offset = this.offset;
    final dx = center?.dx ?? _state!._lastViewSize!.width * 0.5;
    final dy = center?.dy ?? _state!._lastViewSize!.height * 0.5;
    final left = clampX((offset.dx + dx) * ratio - dx, zoomRatio);
    final top = clampY((offset.dy + dy) * ratio - dy, zoomRatio);
    return Matrix4.compose(
      math64.Vector3(-left, -top, 0),
      math64.Quaternion.identity(),
      math64.Vector3(zoomRatio, zoomRatio, 1),
    );
  }

  /// Set zoom ratio.
  ///
  /// [center] specifies the center of the zoom operation in widget's local coordinates.
  /// e.g. tap-position in the widget; most likely to [ScaleStartDetails.localFocalPoint].
  Future<void> setZoomRatio({
    required double zoomRatio,
    Offset? center,
    Duration duration = const Duration(milliseconds: 200),
  }) =>
      _state!._goTo(
        destination: zoomMatrix(zoomRatio, center: center),
        duration: duration,
      );

  /// Current view offset (top-left corner coordinates).
  Offset get offset => Offset(-value.row0[3], -value.row1[3]);

  /// Current view rectangle.
  ///
  /// If the controller is not ready([isReady]), the property throws some exception.
  Rect get viewRect => Rect.fromLTWH(-value.row0[3], -value.row1[3],
      _state!._lastViewSize!.width, _state!._lastViewSize!.height);

  /// Current view zoom ratio.
  ///
  /// If the controller is not ready([isReady]), the property throws some exception.
  double get zoomRatio => value.row0[0];

  /// Get list of the page numbers of the pages visible inside the viewport.
  ///
  /// The map keys are the page numbers.
  ///
  /// And each page number is associated to the page area (width x height) exposed to the viewport;
  /// If the controller is not ready([isReady]), the property throws some exception.
  Map<int, double> get visiblePages => _state!._visiblePages;

  /// Get the current page number by obtaining the page that has the largest area from [visiblePages].
  ///
  /// If no pages are visible, it returns 1.
  /// If the controller is not ready([isReady]), the property throws some exception.
  int get currentPageNumber {
    MapEntry<int, double>? max;
    for (final v in visiblePages.entries) {
      if (max == null || max.value < v.value) {
        max = v;
      }
    }
    return max?.key ?? 1;
  }
}

typedef OnPdfViewerControllerInitialized = void Function(PdfViewerController);

typedef OnClickOutsidePageViewer = void Function();

@immutable
class PdfViewerParams {
  /// Page number to show on the first time.
  final int? pageNumber;

  /// Padding for the every page.
  final double? padding;

  /// Custom page layout logic if you need it.
  final LayoutPagesFunc? layoutPages;

  /// Custom page placeholder that is shown until the page is fully loaded.
  final BuildPageContentFunc? buildPagePlaceholder;

  /// Custom overlay that is shown on page.
  ///
  /// For example, drawings, annotations on pages.
  final BuildPageContentFunc? buildPageOverlay;

  /// Custom page decoration such as drop-shadow.
  final BoxDecoration? pageDecoration;

  /// Scrolling direction.
  final Axis scrollDirection;

  // See [InteractiveViewer] for more info.
  final PanAxis panAxis;

  /// See [InteractiveViewer] for more info.
  @Deprecated(
    'Use panAxis instead. '
    'This feature was deprecated after flutter sdk v3.3.0-0.5.pre.',
  )
  final bool alignPanAxis;

  /// See [InteractiveViewer] for more info.
  final EdgeInsets boundaryMargin;

  /// See [InteractiveViewer] for more info.
  final bool panEnabled;

  /// See [InteractiveViewer] for more info.
  final bool scaleEnabled;

  /// See [InteractiveViewer] for more info.
  final double maxScale;

  /// See [InteractiveViewer] for more info.
  final double minScale;

  /// Whether to allow use of antialiasing on iOS Quartz PDF rendering.
  final bool allowAntialiasingIOS;

  /// See [InteractiveViewer] for more info.
  final GestureScaleEndCallback? onInteractionEnd;

  /// See [InteractiveViewer] for more info.
  final GestureScaleStartCallback? onInteractionStart;

  /// See [InteractiveViewer] for more info.
  final GestureScaleUpdateCallback? onInteractionUpdate;

  /// Callback that is called on viewer initialization.
  ///
  /// It is called on every document load.
  final OnPdfViewerControllerInitialized? onViewerControllerInitialized;

  /// Set the scroll amount ratio by mouse wheel. The default is 0.1.
  ///
  /// Negative value to scroll opposite direction.
  /// null to disable scroll-by-mouse-wheel.
  final double? scrollByMouseWheel;

  /// Changes the deceleration behavior after a gesture.
  ///
  /// Defaults to 0.0000135.
  ///
  /// Cannot be null, and must be a finite number greater than zero.
  final double interactionEndFrictionCoefficient;

  /// Listen event click outside page document viewer
  final OnClickOutsidePageViewer? onClickOutSidePageViewer;

  /// Initializes the parameters.
  const PdfViewerParams(
      {this.pageNumber,
      this.padding,
      this.layoutPages,
      this.buildPagePlaceholder,
      this.buildPageOverlay,
      this.pageDecoration,
      this.scrollDirection = Axis.vertical,
      this.panAxis = PanAxis.free,
      this.alignPanAxis = false,
      this.boundaryMargin = EdgeInsets.zero,
      this.maxScale = 20,
      this.minScale = 0.1,
      this.allowAntialiasingIOS = true,
      this.onInteractionEnd,
      this.onInteractionStart,
      this.onInteractionUpdate,
      this.panEnabled = true,
      this.scaleEnabled = true,
      this.onViewerControllerInitialized,
      this.scrollByMouseWheel = 0.1,
      this.interactionEndFrictionCoefficient = 0.0000135,
      this.onClickOutSidePageViewer});

  PdfViewerParams copyWith({
    int? pageNumber,
    double? padding,
    LayoutPagesFunc? layoutPages,
    BuildPageContentFunc? buildPagePlaceholder,
    BuildPageContentFunc? buildPageOverlay,
    BoxDecoration? pageDecoration,
    Axis? scrollDirection,
    PanAxis? panAxis,
    bool? alignPanAxis,
    EdgeInsets? boundaryMargin,
    bool? panEnabled,
    bool? scaleEnabled,
    double? maxScale,
    double? minScale,
    GestureScaleEndCallback? onInteractionEnd,
    GestureScaleStartCallback? onInteractionStart,
    GestureScaleUpdateCallback? onInteractionUpdate,
    OnPdfViewerControllerInitialized? onViewerControllerInitialized,
    double? scrollByMouseWheel,
    OnClickOutsidePageViewer? onClickOutSidePageViewer,
  }) =>
      PdfViewerParams(
        pageNumber: pageNumber ?? this.pageNumber,
        padding: padding ?? this.padding,
        layoutPages: layoutPages ?? this.layoutPages,
        buildPagePlaceholder: buildPagePlaceholder ?? this.buildPagePlaceholder,
        buildPageOverlay: buildPageOverlay ?? this.buildPageOverlay,
        pageDecoration: pageDecoration ?? this.pageDecoration,
        scrollDirection: scrollDirection ?? this.scrollDirection,
        panAxis: panAxis ?? this.panAxis,
        alignPanAxis: alignPanAxis ?? this.alignPanAxis,
        boundaryMargin: boundaryMargin ?? this.boundaryMargin,
        panEnabled: panEnabled ?? this.panEnabled,
        scaleEnabled: scaleEnabled ?? this.scaleEnabled,
        maxScale: maxScale ?? this.maxScale,
        minScale: minScale ?? this.minScale,
        onInteractionEnd: onInteractionEnd ?? this.onInteractionEnd,
        onInteractionStart: onInteractionStart ?? this.onInteractionStart,
        onInteractionUpdate: onInteractionUpdate ?? this.onInteractionUpdate,
        onViewerControllerInitialized:
            onViewerControllerInitialized ?? this.onViewerControllerInitialized,
        scrollByMouseWheel: scrollByMouseWheel ?? this.scrollByMouseWheel,
        onClickOutSidePageViewer: onClickOutSidePageViewer ?? this.onClickOutSidePageViewer,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfViewerParams &&
        other.pageNumber == pageNumber &&
        other.padding == padding &&
        other.layoutPages == layoutPages &&
        other.buildPagePlaceholder == buildPagePlaceholder &&
        other.buildPageOverlay == buildPageOverlay &&
        other.pageDecoration == pageDecoration &&
        other.scrollDirection == scrollDirection &&
        other.panAxis == panAxis &&
        other.alignPanAxis == alignPanAxis &&
        other.boundaryMargin == boundaryMargin &&
        other.panEnabled == panEnabled &&
        other.scaleEnabled == scaleEnabled &&
        other.maxScale == maxScale &&
        other.minScale == minScale &&
        other.onInteractionEnd == onInteractionEnd &&
        other.onInteractionStart == onInteractionStart &&
        other.onInteractionUpdate == onInteractionUpdate &&
        other.onViewerControllerInitialized == onViewerControllerInitialized &&
        other.scrollByMouseWheel == scrollByMouseWheel &&
        other.onClickOutSidePageViewer == onClickOutSidePageViewer;
  }

  @override
  int get hashCode {
    return pageNumber.hashCode ^
        padding.hashCode ^
        layoutPages.hashCode ^
        buildPagePlaceholder.hashCode ^
        buildPageOverlay.hashCode ^
        pageDecoration.hashCode ^
        scrollDirection.hashCode ^
        panAxis.hashCode ^
        alignPanAxis.hashCode ^
        boundaryMargin.hashCode ^
        panEnabled.hashCode ^
        scaleEnabled.hashCode ^
        maxScale.hashCode ^
        minScale.hashCode ^
        onInteractionEnd.hashCode ^
        onInteractionStart.hashCode ^
        onInteractionUpdate.hashCode ^
        onViewerControllerInitialized.hashCode ^
        scrollByMouseWheel.hashCode ^
        onClickOutSidePageViewer.hashCode;
  }
}

/// A PDF viewer implementation with user interactive zooming support.
class PdfViewer extends StatefulWidget {
  /// PDF document instance.
  final FutureOr<PdfDocument> doc;

  /// Controller for the viewer. If none is specified, the viewer initializes one internally.
  final PdfViewerController? viewerController;

  /// Additional parameter to configure the viewer.
  final PdfViewerParams? params;

  /// Error handler.
  final OnError? onError;

  /// Error-safe wrapper on [doc].
  late final _docCache = _PdfDocumentAwaiter(doc, onError: onError);

  Future<PdfDocument?> get _doc => _docCache.getValue();

  PdfViewer({
    Key? key,
    required this.doc,
    this.viewerController,
    this.params,
    this.onError,
  }) : super(key: key);

  /// Open a file.
  factory PdfViewer.openFile(
    String filePath, {
    Key? key,
    PdfViewerController? viewerController,
    PdfViewerParams? params,
    OnError? onError,
  }) =>
      PdfViewer(
        key: key,
        doc: PdfDocument.openFile(filePath),
        viewerController: viewerController,
        params: params,
        onError: onError,
      );

  /// Open an asset.
  factory PdfViewer.openAsset(
    String assetPath, {
    Key? key,
    PdfViewerController? viewerController,
    PdfViewerParams? params,
    OnError? onError,
  }) =>
      PdfViewer(
        key: key,
        doc: PdfDocument.openAsset(assetPath),
        viewerController: viewerController,
        params: params,
        onError: onError,
      );

  /// Open PDF data on byte array.
  factory PdfViewer.openData(
    Uint8List data, {
    Key? key,
    PdfViewerController? viewerController,
    PdfViewerParams? params,
    OnError? onError,
  }) =>
      PdfViewer(
        key: key,
        doc: PdfDocument.openData(data),
        viewerController: viewerController,
        params: params,
        onError: onError,
      );

  /// Open PDF from the filename returned by async function.
  static Widget openFutureFile(
    Future<String> Function() getFilePath, {
    Key? key,
    PdfViewerController? viewerController,
    PdfViewerParams? params,
    OnError? onError,
    Widget Function(BuildContext)? loadingBannerBuilder,
    PdfDocument? docFallback,
  }) =>
      openFuture(
        getFilePath,
        PdfDocument.openFile,
        key: key,
        viewerController: viewerController,
        params: params,
        onError: onError,
        loadingBannerBuilder: loadingBannerBuilder,
        docFallback: docFallback,
      );

  /// Open PDF data on byte array returned by async function.
  static Widget openFutureData(
    Future<Uint8List> Function() getData, {
    Key? key,
    PdfViewerController? viewerController,
    PdfViewerParams? params,
    OnError? onError,
    Widget Function(BuildContext)? loadingBannerBuilder,
    PdfDocument? docFallback,
  }) =>
      openFuture(
        getData,
        PdfDocument.openData,
        key: key,
        viewerController: viewerController,
        params: params,
        onError: onError,
        loadingBannerBuilder: loadingBannerBuilder,
        docFallback: docFallback,
      );

  /// Open PDF using async function.
  static Widget openFuture<T>(
    Future<T> Function() getFuture,
    Future<PdfDocument> Function(T) futureToDocument, {
    Key? key,
    PdfViewerController? viewerController,
    PdfViewerParams? params,
    OnError? onError,
    Widget Function(BuildContext)? loadingBannerBuilder,
    PdfDocument? docFallback,
  }) =>
      FutureBuilder<T>(
        key: key,
        future: getFuture(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data != null) {
            return PdfViewer(
              doc: futureToDocument(data),
              viewerController: viewerController,
              params: params,
              onError: onError,
            );
          } else if (loadingBannerBuilder != null) {
            return Builder(builder: loadingBannerBuilder);
          } else if (docFallback != null) {
            return PdfViewer(
              doc: Future.value(docFallback),
              viewerController: viewerController,
              params: params,
              onError: onError,
            );
          }
          return Container(); // ultimate fallback
        },
      );

  @override
  PdfViewerState createState() => PdfViewerState();
}

class PdfViewerState extends State<PdfViewer>
    with SingleTickerProviderStateMixin {
  PdfDocument? _doc;
  List<_PdfPageState>? _pages;
  final _pendedPageDisposes = <_PdfPageState>[];
  final _myController = PdfViewerController();
  Size? _lastViewSize;
  Timer? _realSizeUpdateTimer;
  Size? _docSize;
  final Map<int, double> _visiblePages = <int, double>{};

  late AnimationController _animController;
  Animation<Matrix4>? _animGoTo;

  bool _firstControllerAttach = true;
  bool _forceUpdatePagePreviews = true;

  PdfViewerController get _controller =>
      widget.viewerController ?? _myController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _init();
  }

  @override
  void didUpdateWidget(PdfViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkUpdates(oldWidget);
  }

  Future<void> _checkUpdates(PdfViewer oldWidget) async {
    if ((await widget._doc) != (await oldWidget._doc)) {
      _init();
    } else {
      widget.params?.onViewerControllerInitialized?.call(_controller);
      _moveToInitialPositionIfSpecified(
          oldPageNumber: oldWidget.params?.pageNumber);
    }
  }

  void _init() {
    _controller.removeListener(_determinePagesToShow);
    _controller._setViewerState(null);
    _load();
  }

  @override
  void dispose() {
    _cancelLastRealSizeUpdate();
    _releasePages();
    _releaseDocument();
    _handlePendedPageDisposes();
    _controller.removeListener(_determinePagesToShow);
    _controller._setViewerState(null);
    _myController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _releasePages();
    _doc = await widget._doc;

    if (_doc != null) {
      final pages = <_PdfPageState>[];
      try {
        final firstPage = await _doc!.getPage(1);
        final pageSize1 = Size(firstPage.width, firstPage.height);
        for (int i = 0; i < _doc!.pageCount; i++) {
          pages.add(_PdfPageState._(pageNumber: i + 1, pageSize: pageSize1));
        }
      } catch (e) {/* ignore errors anyway */}
      _firstControllerAttach = true;
      _pages = pages;
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _releasePages() {
    if (_pages == null) return;
    for (final p in _pages!) {
      p.releaseTextures();
    }
    _pendedPageDisposes.addAll(_pages!);
    _pages = null;
  }

  void _releaseDocument() {
    _doc?.dispose();
    _doc = null;
  }

  void _handlePendedPageDisposes() {
    for (final p in _pendedPageDisposes) {
      p.releaseTextures();
    }
    _pendedPageDisposes.clear();
  }

  @override
  Widget build(BuildContext context) {
    Future.microtask(_handlePendedPageDisposes);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        _relayout(viewSize);
        final docSize = _docSize ?? const Size(10, 10); // dummy size
        return iv.InteractiveViewer(
          transformationController: _controller,
          constrained: false,
          panAxis: widget.params?.panAxis ?? PanAxis.free,
          onWheelDelta: widget.params?.scrollByMouseWheel != null
              ? _onWheelDelta
              : null,
          boundaryMargin: widget.params?.boundaryMargin ?? EdgeInsets.zero,
          minScale: widget.params?.minScale ?? 0.8,
          maxScale: widget.params?.maxScale ?? 2.5,
          onInteractionEnd: widget.params?.onInteractionEnd,
          onInteractionStart: widget.params?.onInteractionStart,
          onInteractionUpdate: widget.params?.onInteractionUpdate,
          panEnabled: widget.params?.panEnabled ?? true,
          scaleEnabled: widget.params?.scaleEnabled ?? true,
          interactionEndFrictionCoefficient:
              widget.params?.interactionEndFrictionCoefficient ?? 0.0000135,
          child: Stack(
            children: <Widget>[
              if (widget.params?.onClickOutSidePageViewer != null)
                GestureDetector(
                  onTap: widget.params?.onClickOutSidePageViewer,
                  child: Container(
                    width: docSize.width,
                    height: docSize.height,
                    color: Colors.transparent,
                  ),
                )
              else
                SizedBox(width: docSize.width, height: docSize.height),
              ...iterateLaidOutPages(viewSize)
            ],
          ),
        );
      },
    );
  }

  void _onWheelDelta(Offset delta) {
    final m = _controller.value.clone();
    m.translate(
      -delta.dx * widget.params!.scrollByMouseWheel!,
      -delta.dy * widget.params!.scrollByMouseWheel!,
    );
    _controller.value = m;
  }

  double get _padding => widget.params?.padding ?? 8.0;

  void _relayout(Size? viewSize) {
    if (_pages == null) {
      return;
    }
    if (widget.params?.layoutPages == null) {
      _relayoutDefault(viewSize!);
    } else {
      final contentSize =
          Size(viewSize!.width - _padding * 2, viewSize.height - _padding * 2);
      final rects = widget.params!.layoutPages!(
          contentSize, _pages!.map((p) => p.pageSize).toList());
      var allRect = Rect.fromLTWH(0, 0, viewSize.width, viewSize.height);
      for (int i = 0; i < _pages!.length; i++) {
        final rect = rects[i].translate(_padding, _padding);
        _pages![i].rect = rect;
        allRect = allRect.expandToInclude(rect.inflate(_padding));
      }
      _docSize = allRect.size;
    }
    _lastViewSize = viewSize;

    if (_firstControllerAttach) {
      _firstControllerAttach = false;

      Future.delayed(Duration.zero, () {
        // NOTE: controller should be associated after first layout calculation finished.
        _controller.addListener(_determinePagesToShow);
        _controller._setViewerState(this);
        widget.params?.onViewerControllerInitialized?.call(_controller);

        if (mounted) {
          _moveToInitialPositionIfSpecified();
          _forceUpdatePagePreviews = true;
          _determinePagesToShow();
        }
      });
      return;
    }

    _determinePagesToShow();
  }

  void _moveToInitialPositionIfSpecified({int? oldPageNumber}) {
    Matrix4? m;

    // if the pageNumber is explicitly specified and changed from the previous one,
    // move to that page.
    final newPageNumber = widget.params?.pageNumber;
    if (oldPageNumber != newPageNumber && newPageNumber != null) {
      m = _controller.calculatePageFitMatrix(
        pageNumber: newPageNumber,
        padding: widget.params!.padding,
      );
    }

    if (m != null) {
      _controller.value = m;
    }
  }

  /// Default page layout logic that layouts pages vertically or horizontally.
  void _relayoutDefault(Size viewSize) {
    if (widget.params?.scrollDirection == Axis.horizontal) {
      final maxHeight = _pages!.fold<double>(
          0.0, (maxHeight, page) => max(maxHeight, page.pageSize.height));
      final ratio = (viewSize.height - _padding * 2) / maxHeight;
      var left = _padding;
      for (int i = 0; i < _pages!.length; i++) {
        final page = _pages![i];
        final w = page.pageSize.width * ratio;
        final h = page.pageSize.height * ratio;
        page.rect = Rect.fromLTWH(left, _padding, w, h);
        left += w + _padding;
      }
      _docSize = Size(left, viewSize.height);
    } else {
      final maxWidth = _pages!.fold<double>(
          0.0, (maxWidth, page) => max(maxWidth, page.pageSize.width));
      final ratio = (viewSize.width - _padding * 2) / maxWidth;
      var top = _padding;
      for (int i = 0; i < _pages!.length; i++) {
        final page = _pages![i];
        final w = page.pageSize.width * ratio;
        final h = page.pageSize.height * ratio;
        page.rect = Rect.fromLTWH(_padding, top, w, h);
        top += h + _padding;
      }
      _docSize = Size(viewSize.width, top);
    }
  }

  Iterable<Widget> iterateLaidOutPages(Size viewSize) sync* {
    if (!_firstControllerAttach && _pages != null) {
      final m = _controller.value;
      final r = m.row0[0];
      final exposed =
          Rect.fromLTWH(-m.row0[3], -m.row1[3], viewSize.width, viewSize.height)
              .inflate(_padding);

      for (final page in _pages!) {
        if (page.rect == null) continue;
        final pageRectZoomed = Rect.fromLTRB(page.rect!.left * r,
            page.rect!.top * r, page.rect!.right * r, page.rect!.bottom * r);
        final part = pageRectZoomed.intersect(exposed);
        page.isVisibleInsideView = !part.isEmpty;
        if (!page.isVisibleInsideView) continue;

        yield Positioned(
          left: page.rect!.left,
          top: page.rect!.top,
          width: page.rect!.width,
          height: page.rect!.height,
          child: Container(
            width: page.rect!.width,
            height: page.rect!.height,
            decoration: widget.params?.pageDecoration ??
                const BoxDecoration(
                    color: Color.fromARGB(255, 250, 250, 250),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black45,
                          blurRadius: 4,
                          offset: Offset(2, 2))
                    ]),
            child: Stack(children: [
              ValueListenableBuilder<int>(
                  valueListenable: page._previewNotifier,
                  builder: (context, value, child) => page.preview != null
                      ? Positioned.fill(
                          child: PdfTexture(textureId: page.preview!.texId))
                      : widget.params?.buildPagePlaceholder != null
                          ? widget.params!.buildPagePlaceholder!(
                              context, page.pageNumber, page.rect!)
                          : Container()),
              ValueListenableBuilder<_RealSize?>(
                  valueListenable: page.realSize,
                  builder: (context, realSize, child) => realSize != null
                      ? Positioned(
                          left: realSize.rect.left,
                          top: realSize.rect.top,
                          width: realSize.rect.width,
                          height: realSize.rect.height,
                          child: PdfTexture(textureId: realSize.texture.texId))
                      : Container()),
              if (widget.params?.buildPageOverlay != null)
                widget.params!.buildPageOverlay!(
                    context, page.pageNumber, page.rect!),
            ]),
          ),
        );
      }
    }
  }

  /// Not to purge loaded page previews if they're "near" from the current exposed view
  static const _extraBufferAroundView = 400.0;

  void _determinePagesToShow() {
    if (_lastViewSize == null || _pages == null) return;
    final m = _controller.value;
    final r = m.row0[0];
    final exposed = Rect.fromLTWH(
            -m.row0[3], -m.row1[3], _lastViewSize!.width, _lastViewSize!.height)
        .inflate(_padding);

    var pagesToUpdate = 0;
    var changeCount = 0;
    _visiblePages.clear();
    for (final page in _pages!) {
      if (page.rect == null) {
        page.isVisibleInsideView = false;
        continue;
      }
      final pageRectZoomed = Rect.fromLTRB(page.rect!.left * r,
          page.rect!.top * r, page.rect!.right * r, page.rect!.bottom * r);
      final part = pageRectZoomed.intersect(exposed);
      final isVisible = !part.isEmpty;
      if (isVisible) {
        _visiblePages[page.pageNumber] = part.width * part.height;
      }
      if (page.isVisibleInsideView != isVisible) {
        page.isVisibleInsideView = isVisible;
        changeCount++;
        if (isVisible) {
          pagesToUpdate++; // the page gets inside the view
        }
      }
    }

    _cancelLastRealSizeUpdate();

    if (changeCount > 0) {
      _needRelayout();
    }
    if (pagesToUpdate > 0 || _forceUpdatePagePreviews) {
      _needPagePreviewGeneration();
    } else {
      _needRealSizeOverlayUpdate();
    }
  }

  void _needRelayout() {
    Future.delayed(Duration.zero, () => setState(() {}));
  }

  void _needPagePreviewGeneration() {
    Future.delayed(Duration.zero, () => _updatePageState());
  }

  Future<void> _updatePageState() async {
    try {
      if (_pages == null) return;
      _forceUpdatePagePreviews = false;
      for (final page in _pages!) {
        if (page.rect == null) continue;
        final m = _controller.value;
        final r = m.row0[0];
        final exposed = Rect.fromLTWH(-m.row0[3], -m.row1[3],
                _lastViewSize!.width, _lastViewSize!.height)
            .inflate(_extraBufferAroundView);

        final pageRectZoomed = Rect.fromLTRB(page.rect!.left * r,
            page.rect!.top * r, page.rect!.right * r, page.rect!.bottom * r);
        final part = pageRectZoomed.intersect(exposed);
        if (part.isEmpty) continue;

        if (page.status == _PdfPageLoadingStatus.notInitialized) {
          page.status = _PdfPageLoadingStatus.initializing;
          final pdfPage = await _doc!.getPage(page.pageNumber);
          page.pdfPageCompleter.complete(pdfPage);
          final prevPageSize = page.pageSize;
          page.pageSize = Size(pdfPage.width, pdfPage.height);
          page.status = _PdfPageLoadingStatus.initialized;
          if (prevPageSize != page.pageSize && mounted) {
            _relayout(_lastViewSize);
            return;
          }
        }
        if (page.status == _PdfPageLoadingStatus.initialized) {
          page.status = _PdfPageLoadingStatus.pageLoading;
          final pdfPage = await page.pdfPageCompleter.future;
          page.preview = await PdfPageImageTexture.create(
              pdfDocument: pdfPage.document, pageNumber: page.pageNumber);
          final w = pdfPage.width; // * 2;
          final h = pdfPage.height; // * 2;

          await page.preview!.extractSubrect(
            width: w.toInt(),
            height: h.toInt(),
            fullWidth: w,
            fullHeight: h,
            allowAntialiasingIOS: widget.params?.allowAntialiasingIOS ?? true,
          );
          page.status = _PdfPageLoadingStatus.pageLoaded;
          page.updatePreview();
        }
      }

      _needRealSizeOverlayUpdate();
    } catch (e) {/* ignore errors */}
  }

  void _cancelLastRealSizeUpdate() {
    if (_realSizeUpdateTimer != null) {
      _realSizeUpdateTimer!.cancel();
      _realSizeUpdateTimer = null;
    }
  }

  final _realSizeOverlayUpdateBufferDuration =
      const Duration(milliseconds: 100);

  void _needRealSizeOverlayUpdate() {
    _cancelLastRealSizeUpdate();
    // Using Timer as cancellable version of [Future.delayed]
    _realSizeUpdateTimer = Timer(
        _realSizeOverlayUpdateBufferDuration, () => _updateRealSizeOverlay());
  }

  Future<void> _updateRealSizeOverlay() async {
    if (_pages == null) {
      return;
    }

    const FULL_PURGE_DIST_THRESHOLD = 33;
    const PARTIAL_REMOVAL_DIST_THRESHOLD = 8;

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final m = _controller.value;
    final r = m.row0[0];
    final exposed = Rect.fromLTWH(
        -m.row0[3], -m.row1[3], _lastViewSize!.width, _lastViewSize!.height);
    final distBase = max(_lastViewSize!.height, _lastViewSize!.width);
    for (final page in _pages!) {
      if (page.rect == null ||
          page.status != _PdfPageLoadingStatus.pageLoaded) {
        continue;
      }
      final pageRectZoomed = Rect.fromLTRB(page.rect!.left * r,
          page.rect!.top * r, page.rect!.right * r, page.rect!.bottom * r);
      final part = pageRectZoomed.intersect(exposed);
      if (part.isEmpty) {
        final dist = (exposed.center - pageRectZoomed.center).distance;
        if (dist > distBase * FULL_PURGE_DIST_THRESHOLD) {
          page.releaseTextures();
        } else if (dist > distBase * PARTIAL_REMOVAL_DIST_THRESHOLD) {
          page.releaseRealSize();
        }
        continue;
      }
      final fw = pageRectZoomed.width * dpr;
      final fh = pageRectZoomed.height * dpr;
      if (page.preview?.hasUpdatedTexture == true &&
          fw <= page.preview!.texWidth! &&
          fh <= page.preview!.texHeight!) {
        // no real-size overlay needed; use preview
        page.realSize.value = null;
      } else {
        // render real-size overlay
        final offset = part.topLeft - pageRectZoomed.topLeft;
        final rect = Rect.fromLTWH(
            offset.dx / r, offset.dy / r, part.width / r, part.height / r);

        final pdfPage = await page.pdfPageCompleter.future;
        final tex = page._textures[page._textureId++ & 1] ??=
            await PdfPageImageTexture.create(
                pdfDocument: pdfPage.document, pageNumber: page.pageNumber);
        final w = (part.width * dpr).toInt();
        final h = (part.height * dpr).toInt();
        await tex.extractSubrect(
          x: (offset.dx * dpr).toInt(),
          y: (offset.dy * dpr).toInt(),
          width: w,
          height: h,
          fullWidth: fw,
          fullHeight: fh,
          allowAntialiasingIOS: widget.params?.allowAntialiasingIOS ?? true,
        );
        page._updateRealSizeOverlay(_RealSize(rect, tex));
      }
    }
  }

  /// Go to the specified location by the matrix.
  Future<void> _goTo(
      {Matrix4? destination,
      Duration duration = const Duration(milliseconds: 200)}) async {
    try {
      if (destination == null) return; // do nothing
      _animGoTo?.removeListener(_updateControllerMatrix);
      _animController.reset();
      _animGoTo = Matrix4Tween(begin: _controller.value, end: destination)
          .animate(_animController);
      _animGoTo!.addListener(_updateControllerMatrix);
      await _animController
          .animateTo(1.0, duration: duration, curve: Curves.easeInOut)
          .orCancel;
    } on TickerCanceled {
      // expected
    }
  }

  void _updateControllerMatrix() {
    _controller.value = _animGoTo!.value;
  }
}

enum _PdfPageLoadingStatus {
  notInitialized,
  initializing,
  initialized,
  pageLoading,
  pageLoaded,
  disposed,
}

/// RealSize overlay.
@immutable
class _RealSize {
  /// Relative position of the realSize overlay.
  final Rect rect;

  final PdfPageImageTexture texture;

  const _RealSize(this.rect, this.texture);

  Future<void> dispose() => texture.dispose();
}

/// Internal page control structure.
class _PdfPageState {
  /// Page number (started at 1).
  final int pageNumber;

  /// [PdfPage] corresponding to the page if available.
  Completer<PdfPage> pdfPageCompleter = Completer<PdfPage>();

  /// Where the page is layed out if available. It can be null to not show in the view.
  Rect? rect;

  /// Size at 72-dpi. During the initialization, the size may be just a copy of the size of the first page.
  Size pageSize;

  /// Preview image of the page rendered at low resolution.
  PdfPageImageTexture? preview;

  final _textures = <PdfPageImageTexture?>[null, null];

  int _textureId = 0;

  /// realSize overlay.
  final realSize = ValueNotifier<_RealSize?>(null);

  /// Whether the page is visible within the view or not.
  bool isVisibleInsideView = false;

  _PdfPageLoadingStatus status = _PdfPageLoadingStatus.notInitialized;

  final _previewNotifier = ValueNotifier<int>(0);

  _PdfPageState._({required this.pageNumber, required this.pageSize});

  void updatePreview() {
    if (status != _PdfPageLoadingStatus.disposed) _previewNotifier.value++;
  }

  void _updateRealSizeOverlay(_RealSize tex) {
    if (status != _PdfPageLoadingStatus.disposed) realSize.value = tex;
  }

  bool releaseRealSize() {
    realSize.value = null;
    _textures[0]?.dispose();
    _textures[0] = null;
    _textures[1]?.dispose();
    _textures[1] = null;
    return true;
  }

  /// Release allocated textures.
  ///
  /// It's always safe to call the method. If all the textures were already released, the method does nothing.
  /// Returns true if textures are really released; otherwise if the method does nothing and returns false.
  bool releaseTextures() => _releaseTextures(_PdfPageLoadingStatus.initialized);

  bool _releaseTextures(_PdfPageLoadingStatus newStatus) {
    preview?.dispose();
    preview = null;
    releaseRealSize();
    status = newStatus;
    return true;
  }

  void dispose() {
    _releaseTextures(_PdfPageLoadingStatus.disposed);
    _previewNotifier.dispose();
    realSize.dispose();
  }
}
