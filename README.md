# Introduction

[pdf_render](https://pub.dartlang.org/packages/pdf_render) is a PDF renderer implementation that supports iOS (>= 8.0), Android (>= API Level 21) and Web. It provides you with intermediate PDF rendering APIs and also easy-to-use Flutter Widgets.

![](https://user-images.githubusercontent.com/1311400/110233932-cc8d3800-7f6a-11eb-90fd-f610c00688a7.gif)

# Install

Add this to your package's `pubspec.yaml` file and execute `flutter pub get`:

```yaml
dependencies:
  pdf_render: ^1.0.3
```

## Web

For Web, you should add `<script>` tags on your `index.html`:

The plugin now utilizes [PDF.js](https://mozilla.github.io/pdf.js/) to support Flutter Web (still very early stage of implementation).

To use the Flutter Web support, you should add the following code just before `<script src="main.dart.js" type="application/javascript"></script>` inside `index.html`:

```html
  <!-- IMPORTANT: load pdfjs files -->
  <script src="https://cdn.jsdelivr.net/npm/pdfjs-dist@2.6.347/build/pdf.js" type="text/javascript"></script>
  <script type="text/javascript">
    pdfjsLib.GlobalWorkerOptions.workerSrc = "https://cdn.jsdelivr.net/npm/pdfjs-dist@2.6.347/build/pdf.worker.min.js";
    pdfRenderOptions = {
      // where cmaps are downloaded from
      cMapUrl: 'https://cdn.jsdelivr.net/npm/pdfjs-dist@2.6.347/cmaps/',
      // The cmaps are compressed in the case
      cMapPacked: true,
      // any other options for pdfjsLib.getDocument.
      // params: {}
    }
  </script>
```

You can use any URL that specify `PDF.js` distribution URL.
`cMapUrl` indicates cmap files base URL and `cMapPacked` determines whether the cmap files are compressed or not.

## iOS/Android

For iOS and Android, no additional task needed.

# Widgets

## Import Widgets Library

Firstly, you must add the following import:

```dart
import 'package:pdf_render/pdf_render_widgets.dart';
```

_BREAKING CHANGE ON 1.0.0: Please note that 1.0.0 removes the old deprecated widgets and now has only `pdf_render_widgets.dart`; it is the rename of `pdf_render_widgets2.dart` in the older (0.X.Y) releases._

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
        body: PdfViewer(assetName: 'assets/hello.pdf', pageNumber: 2); // show the page-2
      )
    );
  }
```

[PdfViewerController](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerController-class.html) can be used to obtain number of pages inside the document and it also provide [goTo](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerController/goTo.html) and [goToPage](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerController/goToPage.html) methods
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
        body: PdfViewer(
          assetName: 'assets/hello.pdf', onViewerControllerInitialized: (PdfViewerController c) {
            controller = c;
            c.goToPage(pageNumber: 3); // scrolling animation to page 3.
          }
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

[PdfViewerController](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerController-class.html) implementation is based on [InteractiveViewer](https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html) and you can use almost all parameters of InteractiveViewer.

### Page decoration

Each page shown in [PdfViewerController](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewerController-class.html) is by default has drop-shadow using [BoxDecoration](https://api.flutter.dev/flutter/painting/BoxDecoration-class.html). You can override the appearance by [pageDecoration](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewer/pageDecoration.html) property.

### Further page appearance customization

[buildPagePlaceholder](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewer/buildPagePlaceholder.html) is used to customize the white blank page that is shown before loading the page contents.

[buildPageOverlay](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfViewer/buildPageOverlay.html) is used to overlay something on every page.

Both functions are defined as [BuildPageContentFunc](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/BuildPageContentFunc.html):

```dart
typedef BuildPageContentFunc = Widget Function(BuildContext context, int pageNumber, Rect pageRect);
```

The third parameter, `pageRect` is location of page in viewer's world coordinates.

## Single page view

The following fragment illustrates the easiest way to render only one page of a PDF document using [PdfDocumentLoader](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfDocumentLoader-class.html). It is suitable for showing PDF thumbnail.

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
          child: PdfDocumentLoader(
            assetName: 'assets/hello.pdf',
            pageNumber: 1,
            pageBuilder: (context, textureBuilder, pageSize) => textureBuilder()
          )
        )
      ),
    );
  }
```

Of course, [PdfDocumentLoader](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfDocumentLoader-class.html) accepts one of `filePath`, `assetName`, or `data` to load PDF document from a file, or other sources.

## Multi-page view using ListView.builder

Using [PdfDocumentLoader](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfDocumentLoader-class.html) in combination with [PdfPageView](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfPageView-class.html), you can show multiple pages of a PDF document. In the following fragment, `ListView.builder` is utilized to realize scrollable PDF document viewer.

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
          child: PdfDocumentLoader(
            assetName: 'assets/hello.pdf',
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

Both [PdfDocumentLoader](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfDocumentLoader-class.html) and [PdfPageView](https://pub.dev/documentation/pdf_render/latest/pdf_render_widgets/PdfPageView-class.html) accepts `pageBuilder` parameter if you want to customize the visual of each page. The following fragment illustrates that:

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
// For Web, file name can be relative path from index.html or any arbitrary URL but affected by CORS.
PdfDocument? doc = await PdfDocument.openAsset('assets/hello.pdf');
if (doc == null) { /* error */ }

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
PdfDocument? docFromAsset = await PdfDocument.openAsset('assets/hello.pdf');

// from a file
// For Web, file name can be relative path from index.html or any arbitrary URL but affected by CORS.
PdfDocument? docFromFile = await PdfDocument.openFile('/somewhere/in/real/file/system/file.pdf');

// from PDF memory image on Uint8List
PdfDocument? docFromData = await PdfDocument.openData(data);
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
  /// If you want to ensure that the [Image] is available, call [createImageIfNotAvailable].
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

  int? get texWidth;
  int? get texHeight;
  bool get hasUpdatedTexture;

  PdfPageImageTexture({required this.pdfDocument, required this.pageNumber, required this.texId});

  /// Create a new Flutter [Texture]. The object should be released by calling [dispose] method after use it.
  static Future<PdfPageImageTexture> create({required PdfDocument pdfDocument, required int pageNumber});

  /// Release the object.
  Future<void> dispose();

  /// Update texture's sub-rectangle ([destX],[destY],[width],[height]) with the sub-rectangle ([srcX],[srcY],[width],[height]) of the PDF page scaled to [fullWidth] x [fullHeight] size.
  /// If [backgroundFill] is true, the sub-rectangle is filled with white before rendering the page content.
  /// The method can also resize the texture if you specify [texWidth] and [texHeight].
  Future<bool> updateRect({
    int destX = 0,
    int destY = 0,
    int? width,
    int? height,
    int srcX = 0,
    int srcY = 0,
    int? texWidth,
    int? texHeight,
    double? fullWidth,
    double? fullHeight,
    bool backgroundFill = true,
  });
}
```

