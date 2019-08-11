import 'package:flutter/material.dart';
import 'package:pdf_render/pdf_render_widgets.dart';

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
            documentBuilder: (context, pdfDocument, pageCount) => LayoutBuilder(
              builder: (context, constraints) => ListView.builder(
                controller: controller,
                itemCount: pageCount,
                itemBuilder: (context, index) => Container(
                  margin: EdgeInsets.all(margin),
                  padding: EdgeInsets.all(padding),
                  color: Colors.black12,
                  child: PdfPageView(
                    pageNumber: index + 1,
                    calculateSize: (pageWidth, pageHeight, aspectRatio) => Size(constraints.maxWidth - wmargin, (constraints.maxWidth - wmargin) / aspectRatio),

                    customizer: (context, page, size) => Stack(
                      alignment: Alignment.bottomCenter,
                      children: <Widget>[
                        if (page != null) page,
                        Text('${index + 1}', style: TextStyle(fontSize: 50)) // adding page number on the bottom of rendered page
                      ],)
                  )
                )
              )
            ),
          )
        )
      ),
    );
  }
}
