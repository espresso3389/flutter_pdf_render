import 'package:flutter/material.dart';
import 'package:pdf_render/pdf_render_widgets2.dart';

void main() => runApp(new MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: const Text('Pdf_render example app'),
        ),
        backgroundColor: Colors.grey,
        body: Center(
          // PdfDocumentLoader loads the specified PDF document.
          // It does not render the pages directly but each PdfPageView below
          // the widget tree renders each page.
          child: PdfDocumentLoader(
            assetName: 'assets/hello.pdf',
            documentBuilder: (context, pdfDocument, pageCount) => ListView.builder(
              itemCount: pageCount,
              // each page is rendered by PdfPageView
              itemBuilder: (context, index) => PdfPageView(
                pageNumber: index + 1,
                // The second paramter, [pageSize] is the original page size in pt.
                // You can determine the final page size shown in the flutter UI using the size
                // and then pass the size to [textureBuilder] function on the third parameter.
                pageBuilder: (context, textureBuilder, pageSize) {
                  //
                  // This illustrates how to decorate the page image with other widgets
                  //
                  return Stack(
                    alignment: Alignment.bottomCenter,
                    children: <Widget>[
                      // the container adds shadow on each page
                      Container(
                        margin: EdgeInsets.all(4.0),
                        padding: EdgeInsets.all(1.0),
                        decoration: BoxDecoration(boxShadow: [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 4,
                            offset: Offset(2, 2)
                          )
                        ]),
                        // textureBuilder builds the actual page image.
                        child: textureBuilder(dontUseTexture: true)
                      ),
                      // adding page number on the bottom of rendered page
                      Text('${index + 1}',
                        style: TextStyle(fontSize: 50))
                    ],
                  );
                },
              )
            ),
          )
        )
      )
    );
  }
}
