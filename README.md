## Notice (2024-01-22)

If you want to move to [pdfrx](https://github.com/espresso3389/pdfrx) but you have some compatibility issues or any other problems or questions, please feel free to open new discussions on [Discussions on pdfrx](https://github.com/espresso3389/pdfrx/discussions/).

## Notice (2023-12-05)

New plugin, named [pdfrx](https://pub.dev/packages/pdfrx), is a better replacement for pdf_render. And pdf_render is now in maintenance mode. **No new features are added to pdf_render.**

New features introduced by [pdfrx](https://pub.dev/packages/pdfrx):

- Desktop platforms support (Windows, macOS, Linux)
- Password protected PDF files support
- Multithreaded PDF rendering
- PdfDocument.openUri
- [pdfium](https://pdfium.googlesource.com/pdfium/) based structure to support more... :)

[pdfrx](https://pub.dev/packages/pdfrx) is not a full drop-in-replacement to pdf_render but I guess it takes less then a hour to change your code to adopt it.

# Introduction

[pdf_render](https://pub.dartlang.org/packages/pdf_render) is a PDF renderer implementation that supports iOS, Android, macOS, and Web. It provides you with [intermediate PDF rendering APIs](#pdf-rendering-apis) and also easy-to-use [Flutter Widgets](#widgets).

## Getting Started

The following fragment illustrates the easiest way to show a PDF file in assets:

```dart
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: const Text('Easiest PDF sample'),
        ),
        backgroundColor: Colors.grey,
        body: PdfViewer.openAsset('assets/hello.pdf')
      )
    );
  }
```

![web-preview](https://user-images.githubusercontent.com/1311400/110233932-cc8d3800-7f6a-11eb-90fd-f610c00688a7.gif)

# Install

Add this to your package's `pubspec.yaml` file and execute `flutter pub get`:

```yaml
dependencies:
  pdf_render: ^1.4.12
```

## Web

For Web, you should add `<script>` tags on your `index.html`:

The plugin utilizes [PDF.js](https://mozilla.github.io/pdf.js/) to support Flutter Web.

To use the Flutter Web support, you should add the following code just before `<script src="main.dart.js" type="application/javascript"></script>` inside `index.html`:

```html
<!-- IMPORTANT: load pdfjs files -->
<script
  src="https://cdn.jsdelivr.net/npm/pdfjs-dist@3.4.120/build/pdf.min.js"
  type="text/javascript"
></script>
<script type="text/javascript">
  pdfjsLib.GlobalWorkerOptions.workerSrc =
    "https://cdn.jsdelivr.net/npm/pdfjs-dist@3.4.120/build/pdf.worker.min.js";
  pdfRenderOptions = {
    // where cmaps are downloaded from
    cMapUrl: "https://cdn.jsdelivr.net/npm/pdfjs-dist@3.4.120/cmaps/",
    // The cmaps are compressed in the case
    cMapPacked: true,
    // any other options for pdfjsLib.getDocument.
    // params: {}
  };
</script>
```

You can use any URL that specify `PDF.js` distribution URL.
`cMapUrl` indicates cmap files base URL and `cMapPacked` determines whether the cmap files are compressed or not.

## iOS/Android

For iOS and Android, no additional task needed.

## macOS

For macOS, there are two notable issues:

- Asset access is not working yet; see [Flutter issue #47681: [macOS] add lookupKeyForAsset to FlutterPluginRegistrar](https://github.com/flutter/flutter/issues/47681)
- Flutter app restrict its capability by enabling [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox) by default. You can change the behavior by editing your app's entitlements files depending on your configuration. See [the discussion below](#deal-with-app-sandbox).
  - [`macos/Runner/Release.entitlements`](https://github.com/espresso3389/flutter_pdf_render/blob/master/example/macos/Runner/Release.entitlements)
  - [`macos/Runner/DebugProfile.entitlements`](https://github.com/espresso3389/flutter_pdf_render/blob/master/example/macos/Runner/DebugProfile.entitlements)

### Deal with App Sandbox

The easiest option to access files on your disk, set [`com.apple.security.app-sandbox`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_app-sandbox) to `false` on your entitlements file though it is not recommended for releasing apps because it completely disables [App Sandbox](https://developer.apple.com/documentation/security/app_sandbox).

Another option is to use [`com.apple.security.files.user-selected.read-only`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_files_user-selected_read-only) along with [file_selector_macos](https://pub.dev/packages/file_selector_macos). The option is better in security than the previous option.

Anyway, the example code for the plugin illustrates how to download and preview internet hosted PDF file. It uses
[`com.apple.security.network.client`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_network_client) along with [flutter_cache_manager](https://pub.dev/packages/flutter_cache_manager):

```xml
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
</dict>
```

For the actual implementation, see [Missing network support?](#missing-network-support) and [the example code](https://github.com/espresso3389/flutter_pdf_render/blob/master/example/lib/main.dart).

# Widgets

## Import Widgets Library

Firstly, you must add the following import:

```dart
import 'package:pdf_render/pdf_render_widgets.dart';
```

## PdfViewer

[PdfViewer](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewer-class.html) is an extensible PDF document viewer widget which supports pinch-zoom.

The following fragment is a simplest use of the widget:

```dart
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: const Text('Pdf_render example app'),
        ),
        backgroundColor: Colors.grey,
        // You can use either PdfViewer.openFile, PdfViewer.openAsset, or PdfViewer.openData
        body: PdfViewer.openAsset(
          'assets/hello.pdf',
          params: PdfViewerParams(pageNumber: 2), // show the page-2
        )
      )
    );
  }
```

In the code above, the code uses [PdfViewer.openAsset](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewer/PdfViewer.openAsset.html) to load a asset PDF file. There are also [PdfViewer.openFile](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewer/PdfViewer.openFile.html) for local file and [PdfViewer.openData](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewer/PdfViewer.openData.html) for `Uint8List` of PDF binary data.

### Missing network support?

A frequent feature request is something like `PdfViewer.openUri`. The plugin does not have it but it's easy to implement it with [flutter_cache_manager](https://pub.dev/packages/flutter_cache_manager):

```dart
FutureBuilder<File>(
  future: DefaultCacheManager().getSingleFile(
    'https://github.com/espresso3389/flutter_pdf_render/raw/master/example/assets/hello.pdf'),
  builder: (context, snapshot) => snapshot.hasData
    ? PdfViewer.openFile(snapshot.data!.path)
    : Container( /* placeholder */),
)
```

### PdfViewerParams

[PdfViewerParams](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerParams-class.html) contains parameters to customize [PdfViewer](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewer-class.html).

It also equips the parameters that are inherited from [InteractiveViewer](https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html). You can use almost all parameters of [InteractiveViewer](https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html).

### PdfViewerController

[PdfViewerController](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerController-class.html) can be used to obtain number of pages in the PDF document.

#### goTo/goToPage/goToPointInPage

It also provide [goTo](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerController/goTo.html) and [goToPage](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerController/goToPage.html) methods
that you can scroll the viewer to make certain page/area of the document visible:

```dart
  @override
  Widget build(BuildContext context) {
    PdfViewerController? controller;
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: const Text('Pdf_render example app'),
        ),
        backgroundColor: Colors.grey,
        body: PdfViewer.openAsset(
          'assets/hello.pdf',
          params: PdfViewerParams(
            // called when the controller is fully initialized
            onViewerControllerInitialized: (PdfViewerController c) {
              controller = c;
              controller.goToPage(pageNumber: 3); // scrolling animation to page 3.
            }
          )
        ),
      ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            FloatingActionButton(
              child: Icon(Icons.first_page),
              onPressed: () => controller.ready?.goToPage(pageNumber: 1),
            ),
            FloatingActionButton(
              child: Icon(Icons.last_page),
              onPressed: () => controller.ready?.goToPage(pageNumber: controller.pageCount),
            ),
          ],
        ),
      ),
    );
  }
```

[goToPointInPage](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerController/goToPointInPage.html) is just another version of [goToPage](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerController/goToPage.html), which also accepts inner-page point and where the point is anchored to.

The following fragment shows page 1's center on the widget's center with the zoom ratio 300%:

```dart
controller.goToPointInPage(
  pageNumber: 1,
  x: 0.5,
  y: 0.5,
  anchor: PdfViewerAnchor.center,
  zoomRatio: 3.0,
);
```

And, if you set `x: 0, y: 0, anchor: PdfViewerAnchor.topLeft`, the behavior is identical to [goToPage](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerController/goToPage.html).

#### setZoomRatio

[setZoomRatio](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerController/setZoomRatio.html) is a method to change zoom ratio without scrolling the view (\*\*\*it's not exactly the true but almost).

The following fragment changes zoom ratio to 2.0:

```dart
controller.setZoomRatio(2.0);
```

During the zoom changing operation, it keeps the center point in the widget being centered.

The following fragment illustrates another use case, zoom-on-double-tap:

```dart
final controller = PdfViewerController();
TapDownDetails? doubleTapDetails;

...

GestureDetector(
  // Supporting double-tap gesture on the viewer.
  onDoubleTapDown: (details) => doubleTapDetails = details,
  onDoubleTap: () => controller.ready?.setZoomRatio(
    zoomRatio: controller.zoomRatio * 1.5,
    center: doubleTapDetails!.localPosition,
  ),
  child: PdfViewer.openAsset(
    'assets/hello.pdf',
    viewerController: controller,
    ...
```

Using [GestureDetector](https://api.flutter.dev/flutter/widgets/GestureDetector-class.html), it firstly captures the double-tap location on [onDoubleTapDown](https://api.flutter.dev/flutter/widgets/GestureDetector/onDoubleTapDown.html). And then, [onDoubleTap](https://api.flutter.dev/flutter/widgets/GestureDetector/onDoubleTap.html) uses the location as the zoom center.

### Managing gestures

[PdfViewer](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewer-class.html) does not support any gestures except panning and pinch-zooming. To support other gestures, you can wrap the widget with [GestureDetector](https://api.flutter.dev/flutter/widgets/GestureDetector-class.html) as explained above.

### Page decoration

Each page shown in [PdfViewer](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewer-class.html) is by default has drop-shadow using [BoxDecoration](https://api.flutter.dev/flutter/painting/BoxDecoration-class.html). You can override the appearance by [PdfViewerParams.pageDecoration](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerParams/pageDecoration.html) property.

### Further page appearance customization

[PdfViewerParams.buildPagePlaceholder](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerParams/buildPagePlaceholder.html) is used to customize the white blank page that is shown before loading the page contents.

[PdfViewerParams.buildPageOverlay](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerParams/buildPageOverlay.html) is used to overlay something on every page.

Both functions are defined as [BuildPageContentFunc](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/BuildPageContentFunc.html):

```dart
typedef BuildPageContentFunc = Widget Function(
  BuildContext context,
  int pageNumber,
  Rect pageRect);
```

The third parameter, `pageRect` is location of page in viewer's world coordinates.

## Single page view

The following fragment illustrates the easiest way to render only one page of a PDF document using [PdfDocumentLoader](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfDocumentLoader-class.html) widget. It is suitable for showing PDF thumbnail.

```dart
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: const Text('Pdf_render example app'),
        ),
        backgroundColor: Colors.grey,
        body: Center(
          child: PdfDocumentLoader.openAsset(
            'assets/hello.pdf',
            pageNumber: 1,
            pageBuilder: (context, textureBuilder, pageSize) => textureBuilder()
          )
        )
      ),
    );
  }
```

Of course, [PdfDocumentLoader](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfDocumentLoader-class.html) has the following factory functions:

- [PdfDocumentLoader.openAsset](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfDocumentLoader/PdfDocumentLoader.openAsset.html)
- [PdfDocumentLoader.openFile](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfDocumentLoader/PdfDocumentLoader.openFile.html)
- [PdfDocumentLoader.openData](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfDocumentLoader/PdfDocumentLoader.openData.html)

## Multi-page view using ListView.builder

Using [PdfDocumentLoader](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfDocumentLoader-class.html) in combination with [PdfPageView](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfPageView-class.html), you can show multiple pages of a PDF document. In the following fragment, `ListView.builder` is utilized to realize scrollable PDF document viewer.

The most important role of [PdfDocumentLoader](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfDocumentLoader-class.html) is to manage life time of [PdfDocument](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfDocument-class.html) and it disposes the document when the widget tree is going to be disposed.

```dart
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: const Text('Pdf_render example app'),
        ),
        backgroundColor: Colors.grey,
        body: Center(
          child: PdfDocumentLoader.openAsset(
            'assets/hello.pdf',
            documentBuilder: (context, pdfDocument, pageCount) => LayoutBuilder(
              builder: (context, constraints) => ListView.builder(
                itemCount: pageCount,
                itemBuilder: (context, index) => Container(
                  margin: EdgeInsets.all(margin),
                  padding: EdgeInsets.all(padding),
                  color: Colors.black12,
                  child: PdfPageView(
                    pdfDocument: pdfDocument,
                    pageNumber: index + 1,
                  )
                )
              )
            ),
          )
        )
      ),
    );
  }
```

## Customizing page widget

Both [PdfDocumentLoader](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfDocumentLoader-class.html) and [PdfPageView](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfPageView-class.html) accepts `pageBuilder` parameter if you want to customize the visual of each page.

The following fragment illustrates that:

```dart
PdfPageView(
  pageNumber: index + 1,
  // pageSize is the PDF page size in pt.
  pageBuilder: (context, textureBuilder, pageSize) {
    //
    // This illustrates how to decorate the page image with other widgets
    //
    return Stack(
      alignment: Alignment.bottomCenter,
      children: <Widget>[
        // the container adds shadow on each page
        Container(
            margin: EdgeInsets.all(margin),
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(boxShadow: [
              BoxShadow(
                  color: Colors.black45,
                  blurRadius: 4,
                  offset: Offset(2, 2))
            ]),
            // textureBuilder builds the actual page image
            child: textureBuilder()),
        // adding page number on the bottom of rendered page
        Text('${index + 1}', style: TextStyle(fontSize: 50))
      ],
    );
  },
)
```

## textureBuilder

`textureBuilder` ([PdfPageTextureBuilder](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfPageTextureBuilder.html)) generates the actual widget that directly corresponding to the page image. The actual widget generated may vary upon the situation. But you can of course customize the behavior of the function with its parameter.

The function is defined as:

```dart
typedef PdfPageTextureBuilder = Widget Function({
  Size? size,
  PdfPagePlaceholderBuilder? placeholderBuilder,
  bool backgroundFill,
  double? renderingPixelRatio
});
```

So if you want to generate widget of an exact size, you can specify `size` explicitly.

Please note that the size is in density-independent pixels. The function is responsible for determining the actual pixel size based on device's pixel density.

`placeholderBuilder` is the final resort that controls the "placeholder" for loading or failure cases.

```dart
/// Creates page placeholder that is shown on page loading or even page load failure.
typedef PdfPagePlaceholderBuilder = Widget Function(Size size, PdfPageStatus status);

/// Page loading status.
enum PdfPageStatus {
  /// The page is currently being loaded.
  loading,
  /// The page load failed.
  loadFailed,
}
```

# PDF rendering APIs

The following fragment illustrates overall usage of [PdfDocument](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfDocument-class.html):

```dart
import 'package:pdf_render/pdf_render.dart';

...

// Open the document using either openFile, openAsset, or openData.
// For Web, file name can be relative path from index.html or any arbitrary URL
// but affected by CORS.
PdfDocument doc = await PdfDocument.openAsset('assets/hello.pdf');

// Get the number of pages in the PDF file
int pageCount = doc!.pageCount;

// The first page is 1
PdfPage page = await doc!.getPage(1);


// For the render function's return, see explanation below
PdfPageImage pageImage = await page.render();

// Now, you can access pageImage!.pixels for raw RGBA data
// ...

// Generating dart:ui.Image cache for later use by imageIfAvailable
await pageImage.createImageIfNotAvailable();

// PDFDocument must be disposed as soon as possible.
doc!.dispose();

```

And then, you can use [PdfPageImage](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfPageImage-class.html) to get the actual RGBA image in [dart:ui.Image](https://api.flutter.dev/flutter/dart-ui/Image-class.html).

To embed the image in the widget tree, you can use [RawImage](https://docs.flutter.io/flutter/widgets/RawImage-class.html):

```dart
@override
Widget build(BuildContext context) {
  return Center(
    child: Container(
      padding: EdgeInsets.all(10.0),
      color: Colors.grey,
      child: Center(
        // before using imageIfAvailable, you should call createImageIfNotAvailable
        child: RawImage(image: pageImage.imageIfAvailable, fit: BoxFit.contain))
    )
  );
}
```

If you just building widget tree, you had better use faster and efficient [PdfPageImageTexture](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfPageImageTexture-class.html).

## PdfDocument.openXXX

On [PdfDocument](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfDocument-class.html) class, there are three functions to open PDF from a real file, an asset file, or a memory data.

```dart
// from an asset file
PdfDocument docFromAsset = await PdfDocument.openAsset('assets/hello.pdf');

// from a file
// For Web, file name can be relative path from index.html or any arbitrary URL
// but affected by CORS.
PdfDocument docFromFile = await PdfDocument.openFile('/somewhere/in/real/file/system/file.pdf');

// from PDF memory image on Uint8List
PdfDocument docFromData = await PdfDocument.openData(data);
```

## PdfDocument members

[PdfDocument](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfDocument-class.html) class overview:

```dart
class PdfDocument {
  /// File path, `asset:[ASSET_PATH]` or `memory:` depending on the content opened.
  final String sourceName;
  /// Number of pages in the PDF document.
  final int pageCount;
  /// PDF major version.
  final int verMajor;
  /// PDF minor version.
  final int verMinor;
  /// Determine whether the PDF file is encrypted or not.
  final bool isEncrypted;
  /// Determine whether the PDF file allows copying of the contents.
  final bool allowsCopying;
  /// Determine whether the PDF file allows printing of the pages.
  final bool allowsPrinting;

  // Get a page by page number (page number starts at 1)
  Future<PdfPage> getPage(int pageNumber);

  // Dispose the instance.
  Future<void> dispose();
}
```

## PdfPage members

[PdfPage](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfPage-class.html) class overview:

```dart
class PdfPage {
  final PdfDocument document; // For internal purpose
  final int pageNumber; // Page number (page number starts at 1)
  final double width; // Page width in points; pixel size on 72-dpi
  final double height; // Page height in points; pixel size on 72-dpi

  // render sub-region of the PDF page.
  Future<PdfPageImage> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    bool backgroundFill = true,
    bool allowAntialiasingIOS = false
  });
}
```

[render](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfPage/render.html) function extracts a sub-region `(x,y)` - `(x + width, y + height)` from scaled `fullWidth` x `fullHeight` PDF page image. All the coordinates are in pixels.

The following fragment renders the page at 300 dpi:

```dart
const scale = 300.0 / 72.0;
const fullWidth = page.width * scale;
const fullHeight = page.height * scale;
var rendered = page.render(
  x: 0,
  y: 0,
  width: fullWidth.toInt(),
  height: fullHeight.toInt(),
  fullWidth: fullWidth,
  fullHeight: fullHeight);
```

## PdfPageImage members

[PdfPageImage](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfPageImage-class.html) class overview:

```dart
class PdfPageImage {
  /// Page number. The first page is 1.
  final int pageNumber;
  /// Left X coordinate of the rendered area in pixels.
  final int x;
  /// Top Y coordinate of the rendered area in pixels.
  final int y;
  /// Width of the rendered area in pixels.
  final int width;
  /// Height of the rendered area in pixels.
  final int height;
  /// Full width of the rendered page image in pixels.
  final int fullWidth;
  /// Full height of the rendered page image in pixels.
  final int fullHeight;
  /// PDF page width in points (width in pixels at 72 dpi).
  final double pageWidth;
  /// PDF page height in points (height in pixels at 72 dpi).
  final double pageHeight;
  /// RGBA pixels in byte array.
  final Uint8List pixels;

  /// Get [dart:ui.Image] for the object.
  Future<Image> createImageIfNotAvailable() async;

  /// Get [Image] for the object if available; otherwise null.
  /// If you want to ensure that the [Image] is available,
  /// call [createImageIfNotAvailable].
  Image? get imageIfAvailable;
}
```

[createImageIfNotAvailable](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfPageImage/createImageIfNotAvailable.html) generates image cache in [dart:ui.Image](https://api.flutter.dev/flutter/dart-ui/Image-class.html) and [imageIfAvailable](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfPageImage/imageIfAvailable.html) returns the cached image if available.

If you just need RGBA byte array, you can use [pixels](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfPageImage/pixels.html) for that purpose. The pixel at `(x,y)` is on `pixels[(x+y*width)*4]`. Anyway, it's highly discouraged to modify the contents directly though it would work correctly.

## PdfPageImageTexture members

[PdfPageImageTexture](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfPageImageTexture-class.html) is to utilize Flutter's [Texture](https://api.flutter.dev/flutter/widgets/Texture-class.html) class to realize faster and resource-saving rendering comparing to [PdfPageImage](https://pub.dev/documentation/pdf_render/latest/pdf_render/PdfPageImage-class.html)/[RawImage](https://api.flutter.dev/flutter/widgets/RawImage-class.html) combination.

```dart
class PdfPageImageTexture {
  final PdfDocument pdfDocument;
  final int pageNumber;
  final int texId;

  bool get hasUpdatedTexture;

  PdfPageImageTexture({required this.pdfDocument, required this.pageNumber, required this.texId});

  /// Create a new Flutter [Texture]. The object should be released by calling [dispose] method after use it.
  static Future<PdfPageImageTexture> create({required PdfDocument pdfDocument, required int pageNumber});

  /// Release the object.
  Future<void> dispose();

  /// Extract sub-rectangle ([x],[y],[width],[height]) of the PDF page scaled to [fullWidth] x [fullHeight] size.
  /// If [backgroundFill] is true, the sub-rectangle is filled with white before rendering the page content.
  Future<bool> extractSubrect({
    int x = 0,
    int y = 0,
    required int width,
    required int height,
    double? fullWidth,
    double? fullHeight,
    bool backgroundFill = true,
  });
}
```

## Custom Page Layout

[PdfViewerParams](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerParams-class.html) has a property [layoutPages](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerParams/layoutPages.html) to customize page layout.

Sometimes, when you're using **Landscape** mode on your Phone or Tablet and you need to show pdf fit to the center of the screen then you can use this code to customize the pdf layout.

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      backgroundColor: Colors.white70,
      body: PdfViewer.openAsset(
        'assets/hello.pdf',
        params: PdfViewerParams(
          layoutPages: (viewSize, pages) {
            List<Rect> rect = [];
            final viewWidth = viewSize.width;
            final viewHeight = viewSize.height;
            final maxHeight = pages.fold<double>(0.0, (maxHeight, page) => max(maxHeight, page.height));
            final ratio = viewHeight / maxHeight;
            var top = 0.0;
            for (var page in pages) {
              final width = page.width * ratio;
              final height = page.height * ratio;
              final left = viewWidth > viewHeight ? (viewWidth / 2) - (width / 2) : 0.0;
              rect.add(Rect.fromLTWH(left, top, width, height));
              top += height + 8 /* padding */;
            }
            return rect;
          },
        ),
      ),
    );
  }
```

#### Preview

<img src="https://raw.githubusercontent.com/chayanforyou/flutter_pdf_render/update_readme/images/layoutPages.gif" width="50%" height="50%">
