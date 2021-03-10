import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as math64;

import 'pdf_render.dart';
import 'src/wrappers/pdf_texture.dart';

/// Function definition to build widget tree for a PDF document.
///
/// [pdfDocument] is the PDF document and it is valid until the corresponding
/// [PdfDocumentLoader] is in the widget tree. It may be null.
/// [pageCount] indicates the number of pages in it.
typedef Widget PdfDocumentBuilder(BuildContext context, PdfDocument? pdfDocument, int pageCount);

/// Function definition to build widget tree corresponding to a PDF page.
///
/// The function used to decorate the rendered PDF page with certain border and/or shadow
/// and sometimes add page number on it.
/// The second parameter [pageSize] is the original page size in pt.
/// You can determine the final page size shown in the flutter UI using the size
/// and then pass the size to [textureBuilder] function on the third parameter,
/// which generates the final [Widget].
typedef PdfPageBuilder = Widget Function(BuildContext context, PdfPageTextureBuilder textureBuilder, Size pageSize);

/// Function definition to generate the actual widget that contains rendered PDF page image.
///
/// [size] should be the page widget size but it can be null if you don't want to calculate it.
/// Unlike the function name, it may generate widget other than [Texture].
/// the function generates a placeholder [Container] for the unavailable page image.
/// Anyway, please note that the size is in screen coordinates; not the actual pixel size of
/// the image. In other words, the function correctly deals with the screen pixel density automatically.
/// [backgroundFill] specifies whether to fill background before rendering actual page content or not.
/// The page content may not have background fill and if the flag is false, it may be rendered with transparent background.
/// [renderingPixelRatio] specifies pixel density for rendering page image. If it is null, the value is obtained by calling `MediaQuery.of(context).devicePixelRatio`.
/// Please note that on iOS Simulator, it always use non-[Texture] rendering pass.
typedef PdfPageTextureBuilder = Widget Function(
    {Size? size, PdfPagePlaceholderBuilder? placeholderBuilder, bool backgroundFill, double? renderingPixelRatio});

/// Creates page placeholder that is shown on page loading or even page load failure.
typedef PdfPagePlaceholderBuilder = Widget Function(Size size, PdfPageStatus status);

/// Page loading status.
enum PdfPageStatus {
  /// The page is currently being loaded.
  loading,

  /// The page load failed.
  loadFailed,
}

/// [PdfDocumentLoader] is a [Widget] that used to load arbitrary PDF document and manages [PdfDocument] instance.
class PdfDocumentLoader extends StatefulWidget {
  final FutureOr<PdfDocument?> doc;

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
    PdfDocumentBuilder? documentBuilder,
    int? pageNumber,
    PdfPageBuilder? pageBuilder,
    Function(dynamic)? onError,
  }) =>
      PdfDocumentLoader._(
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
    PdfDocumentBuilder? documentBuilder,
    int? pageNumber,
    PdfPageBuilder? pageBuilder,
    Function(dynamic)? onError,
  }) =>
      PdfDocumentLoader._(
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
    PdfDocumentBuilder? documentBuilder,
    int? pageNumber,
    PdfPageBuilder? pageBuilder,
    Function(dynamic)? onError,
  }) =>
      PdfDocumentLoader._(
        doc: PdfDocument.openData(data),
        documentBuilder: documentBuilder,
        pageNumber: pageNumber,
        pageBuilder: pageBuilder,
        onError: onError,
      );

  /// Internal purpose only; use one of [PdfDocumentLoader.openFile], [PdfDocumentLoader.openAsset],
  /// or [PdfDocumentLoader.openData].
  PdfDocumentLoader._({
    Key? key,
    required this.doc,
    this.documentBuilder,
    this.pageNumber,
    this.pageBuilder,
    this.onError,
  }) : super(key: key);

  @override
  _PdfDocumentLoaderState createState() => _PdfDocumentLoaderState();
}

class _PdfDocumentLoaderState extends State<PdfDocumentLoader> {
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
      if (_cachedPageSizes == null) _cachedPageSizes = List<Size?>.filled(_doc!.pageCount, null);
      _cachedPageSizes![pageNumber - 1] = size;
    }
  }

  Size? _getPageSize(int? pageNumber) {
    Size? size;
    if (_cachedPageSizes != null && pageNumber! > 0 && pageNumber <= _cachedPageSizes!.length) {
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
    final newDoc = await widget.doc;
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
      _doc = await widget.doc;
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
  /// [PdfDocument] to render. If it is null, the actual document is obtained by locating ancestor [PdfDocumentLoader] widget.
  final PdfDocument? pdfDocument;

  /// Page number of the page to render if only one page should be shown.
  final int? pageNumber;

  /// Function to build page widget tree. It can be null if you want to use the default page builder.
  final PdfPageBuilder? pageBuilder;

  PdfPageView({Key? key, this.pdfDocument, required this.pageNumber, this.pageBuilder}) : super(key: key);

  @override
  _PdfPageViewState createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {
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
      _page = await _doc!.getPage(widget.pageNumber!);
      if (_page == null) {
        _release();
        _size = docLoaderState?._getPageSize(widget.pageNumber);
      } else {
        _size = Size(_page!.width, _page!.height);
        if (docLoaderState != null) docLoaderState._setPageSize(widget.pageNumber!, _size);
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  _PdfDocumentLoaderState? _getPdfDocumentLoaderState() => context.findAncestorStateOfType<_PdfDocumentLoaderState>();

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

  Widget _pageBuilder(BuildContext context, PdfPageTextureBuilder textureBuilder, Size pageSize) {
    return LayoutBuilder(builder: (context, constraints) => textureBuilder());
  }

  Size get _pageSize => _size ?? defaultSize;

  Size _sizeFromConstraints(BoxConstraints constraints, Size pageSize) {
    final ratio = min(constraints.maxWidth / pageSize.width, constraints.maxHeight / pageSize.height);
    return Size(pageSize.width * ratio, pageSize.height * ratio);
  }

  Widget _textureBuilder({
    Size? size,
    PdfPagePlaceholderBuilder? placeholderBuilder,
    bool backgroundFill = true,
    double? renderingPixelRatio,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final finalSize = size ?? _sizeFromConstraints(constraints, _pageSize);
      final finalPlaceholderBuilder = placeholderBuilder ??
          (size, status) =>
              Container(width: size.width, height: size.height, color: Color.fromARGB(255, 220, 220, 220));
      return FutureBuilder<bool>(
          future: _buildTexture(
            size: finalSize,
            backgroundFill: backgroundFill,
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
              return finalPlaceholderBuilder(finalSize, PdfPageStatus.loadFailed);
            }

            return SizedBox(
              width: finalSize.width,
              height: finalSize.height,
              child: PdfTexture(textureId: _texture!.texId),
            );
          });
    });
  }

  Future<bool> _buildTexture({required Size size, bool backgroundFill = true, double? renderingPixelRatio}) async {
    if (_doc == null ||
        widget.pageNumber == null ||
        widget.pageNumber! < 1 ||
        widget.pageNumber! > _doc!.pageCount ||
        _page == null) {
      return true;
    }

    final pixelRatio = renderingPixelRatio ?? MediaQuery.of(context).devicePixelRatio;
    final pixelSize = size * pixelRatio;
    if (_texture == null || _texture!.pdfDocument != _doc || _texture!.pageNumber != widget.pageNumber) {
      _texture?.dispose();
      _texture = await PdfPageImageTexture.create(pdfDocument: _doc!, pageNumber: widget.pageNumber!);
    }
    await _texture!.updateRect(
        width: pixelSize.width.toInt(),
        height: pixelSize.height.toInt(),
        texWidth: pixelSize.width.toInt(),
        texHeight: pixelSize.height.toInt(),
        fullWidth: pixelSize.width,
        fullHeight: pixelSize.height,
        backgroundFill: backgroundFill);

    return true;
  }
}

typedef LayoutPagesFunc = List<Rect> Function(Size contentViewSize, List<Size> pageSizes);
typedef BuildPageContentFunc = Widget Function(BuildContext context, int pageNumber, Rect pageRect);

/// Controller for [PdfViewer].
/// It is derived from [TransformationController] and basically compatible to [ValueNotifier<Matrix4>].
/// So you can pass it to [ValueListenableBuilder<Matrix4>] or such to receive any view status changes.
class PdfViewerController extends TransformationController {
  PdfViewerController();

  /// Associated [_PdfViewerState].
  /// FIXME: I don't think this is a good structure for our purpose...
  _PdfViewerState? _state;

  /// Associate a [_PdfViewerState] to the controller.
  void _setViewerState(_PdfViewerState? state) {
    _state = state;
    this.notifyListeners();
  }

  /// Whether the controller is ready or not.
  /// If the controller is not ready, almost all methods on [PdfViewerController] won't work (throw some exception).
  /// For certain operations, it may be easier to use [ready] method to get [PdfViewerController?] not to execute
  /// methods unless it is ready.
  bool get isReady => _state?._pages != null;

  /// Helper method to return null when the controller is not ready([isReady]).
  /// It is useful if you want ot call methods like [goTo] with the property like the following fragment:
  /// ```dart
  /// controller.ready?.goToPage(pageNumber: 1);
  /// ```
  PdfViewerController? get ready => isReady ? this : null;

  /// Get total page count in the PDF document.
  /// If the controller is not ready([isReady]), the property throws an exception.
  int get pageCount => _state!._pages!.length;

  /// Get page location. If the page is out of view, it returns null.
  /// If the controller is not ready([isReady]), the property throws an exception.
  Rect? getPageRect(int pageNumber) => _state!._pages![pageNumber - 1].rect;

  /// Calculate the matrix that corresponding to the page position.
  /// If the page is out of view, it returns null.
  /// /// If the controller is not ready([isReady]), the property throws an exception.
  Matrix4? calculatePageFitMatrix({required int pageNumber, double? padding}) {
    final rect = getPageRect(pageNumber)?.inflate(padding ?? _state!._padding);
    if (rect == null) return null;
    final scale = _state!._lastViewSize!.width / rect.width;
    final left = max(0.0, min(rect.left, _state!._docSize!.width - _state!._lastViewSize!.width));
    final top = max(0.0, min(rect.top, _state!._docSize!.height - _state!._lastViewSize!.height));
    return Matrix4.compose(
      math64.Vector3(-left, -top, 0),
      math64.Quaternion.identity(),
      math64.Vector3(scale, scale, 1),
    );
  }

  /// Go to the destination specified by the matrix.
  /// To go to a specific page, use [goToPage] method or use [calculatePageFitMatrix] method to calculate the page location matrix.
  /// If [destination] is null, the method does nothing.
  Future<void> goTo({Matrix4? destination, Duration duration = const Duration(milliseconds: 200)}) =>
      _state!._goTo(destination: destination, duration: duration);

  /// Go to the specified page.
  Future<void> goToPage(
          {required int pageNumber, double? padding, Duration duration = const Duration(milliseconds: 500)}) =>
      goTo(destination: calculatePageFitMatrix(pageNumber: pageNumber, padding: padding), duration: duration);

  /// Current view rectangle.
  /// If the controller is not ready([isReady]), the property throws an exception.
  Rect get viewRect =>
      Rect.fromLTWH(-value.row0[3], -value.row1[3], _state!._lastViewSize!.width, _state!._lastViewSize!.height);

  /// Current view zoom ratio.
  /// If the controller is not ready([isReady]), the property throws an exception.
  double get zoomRatio => value.row0[0];

  /// Get list of the page numbers of the pages visible inside the viewport.
  /// The map keys are the page numbers.
  /// And each page number is associated to the page area (width x height) exposed to the viewport;
  /// If the controller is not ready([isReady]), the property throws an exception.
  Map<int, double> get visiblePages => _state!._visiblePages;

  /// Get the current page number by obtaining the page that has the largest area from [visiblePages].
  /// If no pages are visible, it returns 1.
  /// If the controller is not ready([isReady]), the property throws an exception.
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

typedef OnPdfViewerControllerInitialized = void Function(PdfViewerController?);

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
  /// For example, drawings, annotations on pages.
  final BuildPageContentFunc? buildPageOverlay;

  /// Custom page decoration such as drop-shadow.
  final BoxDecoration? pageDecoration;

  /// See [InteractiveViewer] for more info.
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

  /// See [InteractiveViewer] for more info.
  final GestureScaleEndCallback? onInteractionEnd;

  /// See [InteractiveViewer] for more info.
  final GestureScaleStartCallback? onInteractionStart;

  /// See [InteractiveViewer] for more info.
  final GestureScaleUpdateCallback? onInteractionUpdate;

  /// Callback that is called on viewer initialization to notify the actual [PdfViewerController] used by the viewer regardless of specifying [viewerController].
  final OnPdfViewerControllerInitialized? onViewerControllerInitialized;

  /// Initializes the parameters.
  PdfViewerParams({
    this.pageNumber,
    this.padding,
    this.layoutPages,
    this.buildPagePlaceholder,
    this.buildPageOverlay,
    this.pageDecoration,
    this.alignPanAxis = false,
    this.boundaryMargin = EdgeInsets.zero,
    this.maxScale = 20,
    this.minScale = 0.1,
    this.onInteractionEnd,
    this.onInteractionStart,
    this.onInteractionUpdate,
    this.panEnabled = true,
    this.scaleEnabled = true,
    this.onViewerControllerInitialized,
  });

  PdfViewerParams copyWith({
    int? pageNumber,
    double? padding,
    LayoutPagesFunc? layoutPages,
    BuildPageContentFunc? buildPagePlaceholder,
    BuildPageContentFunc? buildPageOverlay,
    BoxDecoration? pageDecoration,
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
  }) =>
      PdfViewerParams(
        pageNumber: pageNumber ?? this.pageNumber,
        padding: padding ?? this.padding,
        layoutPages: layoutPages ?? this.layoutPages,
        buildPagePlaceholder: buildPagePlaceholder ?? this.buildPagePlaceholder,
        buildPageOverlay: buildPageOverlay ?? this.buildPageOverlay,
        pageDecoration: pageDecoration ?? this.pageDecoration,
        alignPanAxis: alignPanAxis ?? this.alignPanAxis,
        boundaryMargin: boundaryMargin ?? this.boundaryMargin,
        panEnabled: panEnabled ?? this.panEnabled,
        scaleEnabled: scaleEnabled ?? this.scaleEnabled,
        maxScale: maxScale ?? this.maxScale,
        minScale: minScale ?? this.minScale,
        onInteractionEnd: onInteractionEnd ?? this.onInteractionEnd,
        onInteractionStart: onInteractionStart ?? this.onInteractionStart,
        onInteractionUpdate: onInteractionUpdate ?? this.onInteractionUpdate,
        onViewerControllerInitialized: onViewerControllerInitialized ?? this.onViewerControllerInitialized,
      );

  @override
  bool operator ==(Object o) {
    if (identical(this, o)) return true;

    return o is PdfViewerParams &&
        o.pageNumber == pageNumber &&
        o.padding == padding &&
        o.layoutPages == layoutPages &&
        o.buildPagePlaceholder == buildPagePlaceholder &&
        o.buildPageOverlay == buildPageOverlay &&
        o.pageDecoration == pageDecoration &&
        o.alignPanAxis == alignPanAxis &&
        o.boundaryMargin == boundaryMargin &&
        o.panEnabled == panEnabled &&
        o.scaleEnabled == scaleEnabled &&
        o.maxScale == maxScale &&
        o.minScale == minScale &&
        o.onInteractionEnd == onInteractionEnd &&
        o.onInteractionStart == onInteractionStart &&
        o.onInteractionUpdate == onInteractionUpdate &&
        o.onViewerControllerInitialized == onViewerControllerInitialized;
  }

  @override
  int get hashCode {
    return pageNumber.hashCode ^
        padding.hashCode ^
        layoutPages.hashCode ^
        buildPagePlaceholder.hashCode ^
        buildPageOverlay.hashCode ^
        pageDecoration.hashCode ^
        alignPanAxis.hashCode ^
        boundaryMargin.hashCode ^
        panEnabled.hashCode ^
        scaleEnabled.hashCode ^
        maxScale.hashCode ^
        minScale.hashCode ^
        onInteractionEnd.hashCode ^
        onInteractionStart.hashCode ^
        onInteractionUpdate.hashCode ^
        onViewerControllerInitialized.hashCode;
  }
}

/// A PDF viewer implementation with user interactive zooming support.
class PdfViewer extends StatefulWidget {
  /// PDF document instance.
  final FutureOr<PdfDocument?> doc;

  /// Controller for the viewer. If none is specified, the viewer initializes one internally.
  final PdfViewerController? viewerController;

  /// Additional parameter to configure the viewer.
  final PdfViewerParams? params;

  PdfViewer({
    Key? key,
    this.doc,
    this.viewerController,
    this.params,
  }) : super(key: key);

  factory PdfViewer.openFile(
    String filePath, {
    PdfViewerController? viewerController,
    PdfViewerParams? params,
  }) =>
      PdfViewer(
        doc: PdfDocument.openFile(filePath),
        viewerController: viewerController,
        params: params,
      );

  factory PdfViewer.openAsset(
    String filePath, {
    PdfViewerController? viewerController,
    PdfViewerParams? params,
  }) =>
      PdfViewer(
        doc: PdfDocument.openAsset(filePath),
        viewerController: viewerController,
        params: params,
      );

  factory PdfViewer.openData(
    Uint8List data, {
    PdfViewerController? viewerController,
    PdfViewerParams? params,
  }) =>
      PdfViewer(
        doc: PdfDocument.openData(data),
        viewerController: viewerController,
        params: params,
      );

  @override
  _PdfViewerState createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> with SingleTickerProviderStateMixin {
  PdfDocument? _doc;
  List<_PdfPageState>? _pages;
  final _myController = PdfViewerController();
  Size? _lastViewSize;
  Timer? _realSizeUpdateTimer;
  Size? _docSize;
  Map<int, double> _visiblePages = Map<int, double>();

  late AnimationController _animController;
  Animation<Matrix4>? _animGoTo;

  bool _firstControllerAttach = true;
  bool _forceUpdatePagePreviews = true;

  PdfViewerController? get _controller => widget.viewerController ?? _myController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: Duration(milliseconds: 200));
    init();
  }

  @override
  void didUpdateWidget(PdfViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    checkUpdates(oldWidget);
  }

  Future<void> checkUpdates(PdfViewer oldWidget) async {
    if ((await widget.doc) != (await oldWidget.doc)) {
      init();
    } else if (oldWidget.params?.pageNumber != widget.params?.pageNumber) {
      widget.params?.onViewerControllerInitialized?.call(_controller);
      if (widget.params?.pageNumber != null) {
        final m = _controller!.calculatePageFitMatrix(
          pageNumber: widget.params!.pageNumber!,
          padding: widget.params!.padding,
        );
        if (m != null) {
          _controller!.value = m;
        }
      }
    }
  }

  void init() {
    _controller?.removeListener(_determinePagesToShow);
    _controller?._setViewerState(null);
    load();
  }

  @override
  void dispose() {
    _cancelLastRealSizeUpdate();
    _releasePages();
    _controller?.removeListener(_determinePagesToShow);
    _controller?._setViewerState(null);
    _myController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    _releasePages();
    _doc = await widget.doc;

    if (_doc != null) {
      final pages = <_PdfPageState>[];
      final firstPage = await _doc!.getPage(1);
      final pageSize1 = Size(firstPage.width, firstPage.height);
      for (int i = 0; i < _doc!.pageCount; i++) {
        pages.add(_PdfPageState._(pageNumber: i + 1, pageSize: pageSize1));
      }
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
      p.dispose();
    }
    _pages = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        _relayout(viewSize);
        final docSize = _docSize ?? Size(10, 10); // dummy size
        return InteractiveViewer(
            transformationController: widget.viewerController ?? _controller,
            constrained: false,
            alignPanAxis: widget.params?.alignPanAxis ?? false,
            boundaryMargin: widget.params?.boundaryMargin ?? EdgeInsets.zero,
            minScale: widget.params?.minScale ?? 0.8,
            maxScale: widget.params?.maxScale ?? 2.5,
            onInteractionEnd: widget.params?.onInteractionEnd,
            onInteractionStart: widget.params?.onInteractionStart,
            onInteractionUpdate: widget.params?.onInteractionUpdate,
            panEnabled: widget.params?.panEnabled ?? true,
            scaleEnabled: widget.params?.scaleEnabled ?? true,
            child: Stack(
              children: <Widget>[
                SizedBox(width: docSize.width, height: docSize.height),
                ...iterateLaidOutPages(viewSize)
              ],
            ));
      },
    );
  }

  double get _padding => widget.params?.padding ?? 8.0;

  void _relayout(Size? viewSize) {
    if (_pages == null) {
      return;
    }
    if (widget.params?.layoutPages == null) {
      _relayoutDefault(viewSize!);
    } else {
      final contentSize = Size(viewSize!.width - _padding * 2, viewSize.height - _padding * 2);
      final rects = widget.params!.layoutPages!(contentSize, _pages!.map((p) => p.pageSize).toList());
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
        _controller!.addListener(_determinePagesToShow);
        _controller!._setViewerState(this);
        widget.params?.onViewerControllerInitialized?.call(_controller);

        if (mounted) {
          if (widget.params?.pageNumber != null) {
            final m = _controller!.calculatePageFitMatrix(pageNumber: widget.params!.pageNumber!);
            if (m != null) {
              _controller!.value = m;
            }
          }
          _forceUpdatePagePreviews = true;
          _determinePagesToShow();
        }
      });
      return;
    }

    _determinePagesToShow();
  }

  /// Default page layout logic that layouts pages vertically.
  void _relayoutDefault(Size viewSize) {
    final maxWidth = _pages!.fold<double>(0.0, (maxWidth, page) => max(maxWidth, page.pageSize.width));
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

  Iterable<Widget> iterateLaidOutPages(Size viewSize) sync* {
    if (!_firstControllerAttach && _pages != null) {
      final m = _controller!.value;
      final r = m.row0[0];
      final exposed = Rect.fromLTWH(-m.row0[3], -m.row1[3], viewSize.width, viewSize.height).inflate(_padding);

      for (final page in _pages!) {
        if (page.rect == null) continue;
        final pageRectZoomed =
            Rect.fromLTRB(page.rect!.left * r, page.rect!.top * r, page.rect!.right * r, page.rect!.bottom * r);
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
            child: Stack(children: [
              ValueListenableBuilder<int>(
                  valueListenable: page._previewNotifier,
                  builder: (context, value, child) => page.preview != null
                      ? Positioned.fill(child: PdfTexture(textureId: page.preview!.texId))
                      : widget.params?.buildPagePlaceholder != null
                          ? widget.params!.buildPagePlaceholder!(context, page.pageNumber, page.rect!)
                          : Container()),
              ValueListenableBuilder<int>(
                  valueListenable: page._realSizeNotifier,
                  builder: (context, value, child) => page.realSizeOverlayRect != null && page.realSize != null
                      ? Positioned(
                          left: page.realSizeOverlayRect!.left,
                          top: page.realSizeOverlayRect!.top,
                          width: page.realSizeOverlayRect!.width,
                          height: page.realSizeOverlayRect!.height,
                          child: PdfTexture(textureId: page.realSize!.texId))
                      : Container()),
              if (widget.params?.buildPageOverlay != null)
                widget.params!.buildPageOverlay!(context, page.pageNumber, page.rect!),
            ]),
            decoration: widget.params?.pageDecoration ??
                BoxDecoration(
                    color: Color.fromARGB(255, 250, 250, 250),
                    boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(2, 2))]),
          ),
        );
      }
    }
  }

  /// Not to purge loaded page previews if they're "near" from the current exposed view
  static final _extraBufferAroundView = 400.0;

  void _determinePagesToShow() {
    if (_lastViewSize == null) return;
    final m = _controller!.value;
    final r = m.row0[0];
    final exposed = Rect.fromLTWH(-m.row0[3], -m.row1[3], _lastViewSize!.width, _lastViewSize!.height);
    var pagesToUpdate = 0;
    var changeCount = 0;
    _visiblePages.clear();
    for (final page in _pages!) {
      if (page.rect == null) {
        page.isVisibleInsideView = false;
        continue;
      }
      final pageRectZoomed =
          Rect.fromLTRB(page.rect!.left * r, page.rect!.top * r, page.rect!.right * r, page.rect!.bottom * r);
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
    _forceUpdatePagePreviews = false;
    for (final page in _pages!) {
      if (page.rect == null) continue;
      final m = _controller!.value;
      final r = m.row0[0];
      final exposed = Rect.fromLTWH(-m.row0[3], -m.row1[3], _lastViewSize!.width, _lastViewSize!.height)
          .inflate(_extraBufferAroundView);

      final pageRectZoomed =
          Rect.fromLTRB(page.rect!.left * r, page.rect!.top * r, page.rect!.right * r, page.rect!.bottom * r);
      final part = pageRectZoomed.intersect(exposed);
      if (part.isEmpty) continue;

      if (page.status == _PdfPageLoadingStatus.notInitialized) {
        page.status = _PdfPageLoadingStatus.initializing;
        page.pdfPage = await _doc!.getPage(page.pageNumber);
        final prevPageSize = page.pageSize;
        page.pageSize = Size(page.pdfPage!.width, page.pdfPage!.height);
        page.status = _PdfPageLoadingStatus.initialized;
        if (prevPageSize != page.pageSize && mounted) {
          _relayout(_lastViewSize);
          return;
        }
      }
      if (page.status == _PdfPageLoadingStatus.initialized) {
        page.status = _PdfPageLoadingStatus.pageLoading;
        page.preview =
            await PdfPageImageTexture.create(pdfDocument: page.pdfPage!.document, pageNumber: page.pageNumber);
        final w = page.pdfPage!.width; // * 2;
        final h = page.pdfPage!.height; // * 2;
        await page.preview!.updateRect(
            width: w.toInt(),
            height: h.toInt(),
            texWidth: w.toInt(),
            texHeight: h.toInt(),
            fullWidth: w,
            fullHeight: h);
        page.status = _PdfPageLoadingStatus.pageLoaded;
        page.updatePreview();
      }
    }

    _needRealSizeOverlayUpdate();
  }

  void _cancelLastRealSizeUpdate() {
    if (_realSizeUpdateTimer != null) {
      _realSizeUpdateTimer!.cancel();
      _realSizeUpdateTimer = null;
    }
  }

  final _realSizeOverlayUpdateBufferDuration = Duration(milliseconds: 100);

  void _needRealSizeOverlayUpdate() {
    _cancelLastRealSizeUpdate();
    _realSizeUpdateTimer = Timer(_realSizeOverlayUpdateBufferDuration, () => _updateRealSizeOverlay());
  }

  Future<void> _updateRealSizeOverlay() async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final m = _controller!.value;
    final r = m.row0[0];
    final exposed = Rect.fromLTWH(-m.row0[3], -m.row1[3], _lastViewSize!.width, _lastViewSize!.height);
    for (final page in _pages!) {
      if (page.rect == null || page.status != _PdfPageLoadingStatus.pageLoaded) continue;
      final pageRectZoomed =
          Rect.fromLTRB(page.rect!.left * r, page.rect!.top * r, page.rect!.right * r, page.rect!.bottom * r);
      final part = pageRectZoomed.intersect(exposed);
      if (part.isEmpty) continue;
      final fw = pageRectZoomed.width * dpr;
      final fh = pageRectZoomed.height * dpr;
      if (page.preview?.hasUpdatedTexture == true && fw <= page.preview!.texWidth! && fh <= page.preview!.texHeight!) {
        // no real-size overlay needed; use preview
        page.realSizeOverlayRect = null;
      } else {
        // render real-size overlay
        final offset = part.topLeft - pageRectZoomed.topLeft;
        page.realSizeOverlayRect = Rect.fromLTWH(offset.dx / r, offset.dy / r, part.width / r, part.height / r);
        page.realSize ??=
            await PdfPageImageTexture.create(pdfDocument: page.pdfPage!.document, pageNumber: page.pageNumber);
        final w = (part.width * dpr).toInt();
        final h = (part.height * dpr).toInt();
        await page.realSize!.updateRect(
            width: w,
            height: h,
            srcX: (offset.dx * dpr).toInt(),
            srcY: (offset.dy * dpr).toInt(),
            texWidth: w,
            texHeight: h,
            fullWidth: fw,
            fullHeight: fh);
        page._updateRealSizeOverlay();
      }
    }
  }

  /// Go to the specified location by the matrix.
  Future<void> _goTo({Matrix4? destination, Duration duration = const Duration(milliseconds: 200)}) async {
    try {
      if (destination == null) return; // do nothing
      _animGoTo?.removeListener(_updateControllerMatrix);
      _animController.reset();
      _animGoTo = Matrix4Tween(begin: _controller!.value, end: destination).animate(_animController);
      _animGoTo!.addListener(_updateControllerMatrix);
      await _animController.animateTo(1.0, duration: duration, curve: Curves.easeInOut).orCancel;
    } on TickerCanceled {
      // expected
    }
  }

  void _updateControllerMatrix() {
    _controller!.value = _animGoTo!.value;
  }
}

enum _PdfPageLoadingStatus { notInitialized, initializing, initialized, pageLoading, pageLoaded }

/// Internal page control structure.
class _PdfPageState {
  /// Page number (started at 1).
  final int pageNumber;

  /// Where the page is layed out if available. It can be null to not show in the view.
  Rect? rect;

  /// [PdfPage] corresponding to the page if available.
  PdfPage? pdfPage;

  /// Size at 72-dpi. During the initialization, the size may be just a copy of the size of the first page.
  Size pageSize;

  /// Preview image of the page rendered at low resolution.
  PdfPageImageTexture? preview;

  /// Relative position of the realSize overlay. null to not show realSize overlay.
  Rect? realSizeOverlayRect;

  /// realSize overlay.
  PdfPageImageTexture? realSize;

  /// Whether the page is visible within the view or not.
  bool isVisibleInsideView = false;

  _PdfPageLoadingStatus status = _PdfPageLoadingStatus.notInitialized;

  final _previewNotifier = ValueNotifier<int>(0);
  final _realSizeNotifier = ValueNotifier<int>(0);

  _PdfPageState._({required this.pageNumber, required this.pageSize});

  void updatePreview() => _previewNotifier.value++;

  void _updateRealSizeOverlay() => _realSizeNotifier.value++;

  /// Release allocated textures.
  /// It's always safe to call the method. If all the textures were already released, the method does nothing.
  /// Returns true if textures are really released; otherwise if the method does nothing and returns false.
  bool releaseTextures() {
    if (preview == null) return false;
    preview!.dispose();
    realSize?.dispose();
    preview = null;
    realSize = null;
    status = _PdfPageLoadingStatus.initialized;
    return true;
  }

  void dispose() {
    releaseTextures();
    _previewNotifier.dispose();
    _realSizeNotifier.dispose();
  }
}
