import Flutter
import UIKit
import CoreGraphics

class Doc {
  let doc: CGPDFDocument
  var pages: [CGPDFPage?]

  init(doc: CGPDFDocument) {
    self.doc = doc
    self.pages = Array<CGPDFPage?>(repeating: nil, count: doc.numberOfPages)
  }
}

public class SwiftPdfRenderPlugin: NSObject, FlutterPlugin {
  static let invalid = NSNumber(value: -1)
  let dispQueue = DispatchQueue(label: "pdf_render")
  var docMap: [Int: Doc] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "pdf_render", binaryMessenger: registrar.messenger())
    let instance = SwiftPdfRenderPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "file"
    {
      guard let pdfFilePath = call.arguments as! String? else {
        result(nil)
        return
      }
      result(register(openFileDoc(pdfFilePath: pdfFilePath)))
    }
    else if call.method == "asset"
    {
      guard let name = call.arguments as! String? else {
        result(nil)
        return
      }
      result(register(openAssetDoc(name: name)))
    }
    else if call.method == "data" {
      guard let data = call.arguments as! FlutterStandardTypedData? else {
        result(nil)
        return
      }
      result(register(openDataDoc(data: data.data)))
    }
    else if call.method == "close"
    {
      if  let id = call.arguments as! NSNumber? {
        close(docId: id.intValue)
      }
      result(NSNumber(value: 0))
    }
    else if call.method == "info"
    {
      guard let docId = call.arguments as! NSNumber? else {
        result(SwiftPdfRenderPlugin.invalid)
        return
      }
      result(getInfo(docId: docId.intValue))
    }
    else if call.method == "page"
    {
      guard let args = call.arguments as! NSDictionary? else {
        result(nil)
        return
      }
      result(openPage(args: args))
    }
    else if call.method == "closePage"
    {
      if  let id = call.arguments as! NSNumber? {
        result(closePage(id: id.intValue))
      }
      result(NSNumber(value: 0))
    }
    else if call.method == "render"
    {
      guard let args = call.arguments as! NSDictionary? else {
        result(SwiftPdfRenderPlugin.invalid)
        return
      }
      renderPdf(args: args, result: result)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  func register(_ doc: CGPDFDocument?) -> NSDictionary? {
    guard doc != nil else { return nil }
    let id = docMap.count
    docMap[id] = Doc(doc: doc!)
    return getInfo(docId: id)
  }

  func getInfo(docId: Int) -> NSDictionary? {
    guard let doc = docMap[docId]?.doc else {
      return nil
    }
    var verMajor: Int32 = 0
    var verMinor: Int32 = 0
    doc.getVersion(majorVersion: &verMajor, minorVersion: &verMinor)

    let dict: [String: Any] = [
      "docId": Int32(docId),
      "pageCount": Int32(doc.numberOfPages),
      "verMajor": verMajor,
      "verMinor": verMinor,
      "isEncrypted": NSNumber(value: doc.isEncrypted),
      "allowsCopying": NSNumber(value: doc.allowsCopying),
      "allowsPrinting": NSNumber(value: doc.allowsPrinting),
      "isUnlocked": NSNumber(value: doc.isUnlocked),
    ]
    return dict as NSDictionary
  }

  func close(docId: Int) -> Void {
    docMap[docId] = nil
  }

  func openDataDoc(data: Data) -> CGPDFDocument? {
    guard let datProv = CGDataProvider(data: data as CFData) else { return nil }
    return CGPDFDocument(datProv)
  }

  func openAssetDoc(name: String) -> CGPDFDocument? {
    guard let path = Bundle.main.path(forResource: "flutter_assets/" + name, ofType: "") else {
      return nil
    }
    return openFileDoc(pdfFilePath: path)
  }

  func openFileDoc(pdfFilePath: String) -> CGPDFDocument? {
    return CGPDFDocument(URL(fileURLWithPath: pdfFilePath) as CFURL)
  }

  func openPage(args: NSDictionary) -> NSDictionary? {
    let docId = args["docId"] as! Int
    guard let doc = docMap[docId] else { return nil }
    let pageNumber = args["pageNumber"] as! Int
    if pageNumber < 1 || pageNumber > doc.pages.count { return nil }
    var page = doc.pages[pageNumber - 1]
    if page == nil {
      page = doc.doc.page(at: pageNumber)
      if page == nil { return nil }
      doc.pages[pageNumber - 1] = page
    }

    let pdfBBox = page!.getBoxRect(.mediaBox)
    let dict: [String: Any] = [
      "docId": Int32(docId),
      "pageNumber": Int32(pageNumber),
      "rotationAngle": Int32(page!.rotationAngle),
      "width": NSNumber(value: Double(pdfBBox.width)),
      "height": NSNumber(value: Double(pdfBBox.height))
    ]
    return dict as NSDictionary
  }

  func closePage(id: Int) {
    docMap[id] = nil
  }

  func renderPdf(args: NSDictionary, result: @escaping FlutterResult) {
    let docId = args["docId"] as! Int
    guard let doc = docMap[docId] else {
      result(SwiftPdfRenderPlugin.invalid)
      return
    }
    let pageNumber = args["pageNumber"] as! Int
    guard pageNumber >= 1 && pageNumber <= doc.pages.count else {
      result(SwiftPdfRenderPlugin.invalid)
      return
    }
    guard let page = doc.pages[pageNumber - 1] else {
      result(SwiftPdfRenderPlugin.invalid)
      return
    }
    let x = args["x"] as! Int
    let y = args["y"] as! Int
    let w = args["width"] as! Int
    let h = args["height"] as! Int
    let fw = args["fullWidth"] as! Int? ?? 0
    let fh = args["fullHeight"] as! Int? ?? 0
    let dpi = args["dpi"] as! Double? ?? 0
    let boxFit = args["boxFit"] as! Bool? ?? false

    dispQueue.async {
      var dict: [String: Any]? = nil
      if let data = renderPdfPageRgba(page: page, x: x, y: y, width: w, height: h, fullWidth: fw, fullHeight: fh, dpi: dpi, boxFit: boxFit) {
        dict = [
          "docId": Int32(docId),
          "pageNumber": Int32(pageNumber),
          "x": Int32(data.x),
          "y": Int32(data.y),
          "width": Int32(data.width),
          "height": Int32(data.height),
          "fullWidth": Int32(data.fullWidth),
          "fullHeight": Int32(data.fullHeight),
          "pageWidth": NSNumber(value: data.pageWidth),
          "pageHeight": NSNumber(value: data.pageHeight),
          "data": FlutterStandardTypedData(bytes: data.data)
        ]
      }
      DispatchQueue.main.async {
        // FIXME: Should we use FlutterBasicMessageChannel<ByteData>?
        result(dict != nil ? (dict! as NSDictionary) : nil)
      }
    }
  }
}

class PageData {
  let x: Int
  let y: Int
  let width: Int
  let height: Int
  let fullWidth: Int
  let fullHeight: Int
  let pageWidth: Double
  let pageHeight: Double
  let data: Data
  init(x: Int, y: Int, width: Int, height: Int, fullWidth: Int, fullHeight: Int, pageWidth: Double, pageHeight: Double, data: Data) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.fullWidth = fullWidth
    self.fullHeight = fullHeight
    self.pageWidth = pageWidth
    self.pageHeight = pageHeight
    self.data = data
  }
}

func renderPdfPageRgba(page: CGPDFPage, x: Int, y: Int, width: Int, height: Int, fullWidth: Int = 0, fullHeight: Int = 0, dpi: Double = 0.0, boxFit: Bool = false) -> PageData? {
  var fw = fullWidth <= 0 ? width : fullWidth
  var fh = fullHeight <= 0 ? height : fullHeight
  // If almost all parameters are 0, render the page at 72 dpi
  var dpiRender = dpi
  if !boxFit && dpi == 0.0 && fw == 0 && fh == 0 {
    dpiRender = 72.0
  }
  
  let pdfBBox = page.getBoxRect(.mediaBox)
  var sx: CGFloat
  var sy: CGFloat
  if dpiRender != 0.0 {
    // size by dpi
    sx = CGFloat(dpiRender / 72.0)
    sy = CGFloat(dpiRender / 72.0)
    fw = Int(sx * pdfBBox.width)
    fh = Int(sy * pdfBBox.height)
  } else {
    // size by fullWidth/fullHeight
    sx = CGFloat(fw) / pdfBBox.width
    sy = CGFloat(fh) / pdfBBox.height
    if boxFit {
      sx = min(sx, sy)
      sy = sx
      fw = Int(sx * pdfBBox.width)
      fh = Int(sy * pdfBBox.height)
      print("PDF boxFit: \(fw)x\(fh)")
    }
  }
  
  let w = width <= 0 ? fw : width
  let h = height <= 0 ? fh : height

  let stride = w * 4
  var data = Data(repeating: 0xff, count: stride * h)
  var success = false
  data.withUnsafeMutableBytes { (ptr: UnsafeMutablePointer<UInt8>) in
    let rgb = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: ptr, width: w, height: h, bitsPerComponent: 8, bytesPerRow: stride, space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    if context != nil {
      context!.translateBy(x: CGFloat(-x), y: CGFloat(-y))
      context!.scaleBy(x: sx, y: sy)
      context!.drawPDFPage(page)
      success = true
    }
  }
  return success ? PageData(
    x: x, y: y,
    width: w, height: h,
    fullWidth: fw, fullHeight: fh,
    pageWidth: Double(pdfBBox.width),
    pageHeight: Double(pdfBBox.height),
    data: data) : nil
}
