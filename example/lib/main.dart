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
            documentBuilder: (context, pdfDocument, pageCount) => pdfDocument == null ? Container() : PdfInteractiveViewer(doc: pdfDocument, padding: 16)
          )
        )
      )
    );
  }
}
