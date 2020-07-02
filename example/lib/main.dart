import 'package:flutter/material.dart';
import 'package:pdf_render/pdf_render_widgets2.dart';

void main() => runApp(new MyApp());

class MyApp extends StatelessWidget {
  /// render at 100 dpi
  static const scale = 100.0 / 72.0;
  static const margin = 4.0;
  static const padding = 1.0;
  static const wmargin = (margin + padding) * 2;
  static final controller = ScrollController();

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
            documentBuilder: (context, pdfDocument, pageCount) =>
                ListView.builder(
                    controller: controller,
                    itemCount: pageCount,
                    itemBuilder: (context, index) => PdfPageView(
                          pageNumber: index + 1,
                          pageBuilder: (context, aspectRatio, textureBuilder) {
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
                                    child: textureBuilder(null)),
                                // adding page number on the bottom of rendered page
                                Text('${index + 1}',
                                    style: TextStyle(fontSize: 50))
                              ],
                            );
                          },
                        )),
          ))),
    );
  }
}
