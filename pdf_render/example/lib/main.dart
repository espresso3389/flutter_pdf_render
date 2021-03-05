import 'package:flutter/material.dart';
import 'package:pdf_render/pdf_render_widgets.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final controller = PdfViewerController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
        home: new Scaffold(
            appBar: new AppBar(
              title: ValueListenableBuilder<Object>(
                  // The controller is compatible with ValueListenable<Matrix4> and you can receive notifications on scrolling and zooming of the view.
                  valueListenable: controller,
                  builder: (context, _, child) =>
                      Text(controller.isReady ? 'Page #${controller.currentPageNumber}' : 'Page -')),
            ),
            backgroundColor: Colors.grey,
            body: PdfViewer(
              assetName: 'assets/hello.pdf',
              padding: 16,
              minScale: 1.0,
              viewerController: controller,
            ),
            floatingActionButton: Column(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[
              FloatingActionButton(
                  heroTag: 'firstPage',
                  child: Icon(Icons.first_page),
                  onPressed: () => controller?.goToPage(pageNumber: 1)),
              FloatingActionButton(
                  heroTag: 'lastPage',
                  child: Icon(Icons.last_page),
                  onPressed: () => controller?.goToPage(pageNumber: controller?.pageCount)),
            ])));
  }
}
