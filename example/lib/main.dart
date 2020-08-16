import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pdf_render/pdf_render_widgets2.dart';

void main() => runApp(new MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    PdfViewerController controller;
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: const Text('Pdf_render example app'),
        ),
        backgroundColor: Colors.grey,
        body: PdfViewer(
          assetName: 'assets/hello.pdf', padding: 16,
          minScale: 1.0,
          onViewerControllerInitialized: (c) { controller = c; },
        ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            FloatingActionButton(heroTag: 'firstPage', child: Icon(Icons.first_page), onPressed: () => controller?.goToPage(pageNumber: 1)),
            FloatingActionButton(heroTag: 'lastPage', child: Icon(Icons.last_page), onPressed: () => controller?.goToPage(pageNumber: controller?.pageCount)),
          ]
        )
      )
    );
  }
}
