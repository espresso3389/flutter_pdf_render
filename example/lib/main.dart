import 'package:flutter/material.dart';
import 'dart:async';

import 'package:pdf_render/pdf_render.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {
  PdfPageImage _pageImage;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    //
    // Loading PDF file
    //
    var doc = await PdfDocument.openAsset('assets/hello.pdf');
    var page = await doc.getPage(1); // The first page is 1
    // render at 100 dpi
    const scale = 100.0 / 72.0;
    var w = (page.width * scale).toInt();
    var h = (page.height * scale).toInt();
    var pageImage = await page.render(width: w, height: h);
    // PDFDocument must be disposed as soon as possible.
    doc.dispose();
    if (!mounted) return;
    setState(() {
      _pageImage = pageImage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: const Text('Pdf_render example app'),
        ),
        body: new Center(
          child: Container(
            padding: EdgeInsets.all(10.0),
            color: Colors.grey,
            child: Center(
              child:
                _pageImage?.image != null ?
                // _pageImage.image is dart:ui.Image and you should wrap it with RawImage
                // to embed it on widget tree.
                RawImage(image: _pageImage.image, fit: BoxFit.contain) : Container()
              )
          )
        ),
      ),
    );
  }
}
