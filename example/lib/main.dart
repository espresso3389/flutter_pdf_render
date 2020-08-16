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
          onViewerControllerInitialized: (c) {
            controller = c;
            //c.value = Matrix4.identity();
            //c.goToPage(pageNumber: 4);
          },
          layoutPages: (contentViewSize, pageSizes) {
            final padding = 16.0;
            double widthLMax = 0, widthRMax = 0;
            for (int i = 0; i < pageSizes.length; i += 2) {
              widthLMax = max(widthLMax, pageSizes[i].width);
              if (i + 1 == pageSizes.length)
                break;
              widthRMax = max(widthRMax, pageSizes[i + 1].width);
            }
            final ratio = (contentViewSize.width - padding) / (widthLMax + widthRMax);
            final widthL = widthLMax * ratio;
            final rects = List<Rect>();
            double top = 0;
            for (int i = 0; i < pageSizes.length; i += 2) {
              final hasPageR = i + 1 < pageSizes.length;
              final pageL = pageSizes[i] * ratio;
              final pageR = hasPageR ? pageSizes[i + 1] * ratio : null;
              final height = hasPageR ? max(pageL.height, pageR.height) : pageL.height;
              rects.add(Rect.fromLTWH(
                widthL - pageL.width,
                top + (height - pageL.height) / 2,
                pageL.width,
                pageL.height));
              if (!hasPageR)
                break;
              rects.add(Rect.fromLTWH(
                padding + widthL,
                top + (height - pageR.height) / 2,
                pageR.width,
                pageR.height));
              top += height + padding;
            }
            return rects;
          },
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
