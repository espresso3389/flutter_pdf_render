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
  let registrar: FlutterPluginRegistrar
  static var newId = 0;
  var docMap: [Int: Doc] = [:]

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "pdf_render", binaryMessenger: registrar.messenger())
    let instance = SwiftPdfRenderPlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "file"
    {
      guard let pdfFilePath = call.arguments as! String? else {
        result(nil)
        return
      }
      result(registerNewDoc(openFileDoc(pdfFilePath: pdfFilePath)))
    }
    else if call.method == "asset"
    {
      guard let name = call.arguments as! String? else {
        result(nil)
        return
      }
      result(registerNewDoc(openAssetDoc(name: name)))
    }
    else if call.method == "data" {
      guard let data = call.arguments as! FlutterStandardTypedData? else {
        result(nil)
        return
      }
      result(registerNewDoc(openDataDoc(data: data.data)))
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
    else if call.method == "render"
    {
      guard let args = call.arguments as! NSDictionary? else {
        result(SwiftPdfRenderPlugin.invalid)
        return
      }
      render(args: args, result: result)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  func registerNewDoc(_ doc: CGPDFDocument?) -> NSDictionary? {
    guard doc != nil else { return nil }
    let id = SwiftPdfRenderPlugin.newId
    SwiftPdfRenderPlugin.newId = SwiftPdfRenderPlugin.newId + 1
    if SwiftPdfRenderPlugin.newId == SwiftPdfRenderPlugin.invalid.intValue { SwiftPdfRenderPlugin.newId = 0 }
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
    let key = registrar.lookupKey(forAsset: name)
    guard let path = Bundle.main.path(forResource: key, ofType: "") else {
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

  func render(args: NSDictionary, result: @escaping FlutterResult) {
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
    let fw = args["fullWidth"] as? Double ?? 0.0
    let fh = args["fullHeight"] as? Double ?? 0.0
    let backgroundFill = args["backgroundFill"] as? Bool ?? false

    dispQueue.async {
      var dict: [String: Any]? = nil
      if let data = renderPdfPageRgba(page: page, x: x, y: y, width: w, height: h, fullWidth: fw, fullHeight: fh, backgroundFill: backgroundFill) {
        dict = [
          "docId": Int32(docId),
          "pageNumber": Int32(pageNumber),
          "x": Int32(data.x),
          "y": Int32(data.y),
          "width": Int32(data.width),
          "height": Int32(data.height),
          "fullWidth": NSNumber(value: data.fullWidth),
          "fullHeight": NSNumber(value: data.fullHeight),
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
  let fullWidth: Double
  let fullHeight: Double
  let pageWidth: Double
  let pageHeight: Double
  let data: Data
  init(x: Int, y: Int, width: Int, height: Int, fullWidth: Double, fullHeight: Double, pageWidth: Double, pageHeight: Double, data: Data) {
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

func renderPdfPageRgba(page: CGPDFPage, x: Int, y: Int, width: Int, height: Int, fullWidth: Double = 0.0, fullHeight: Double = 0.0, backgroundFill: Bool = false) -> PageData? {

  let pdfBBox = page.getBoxRect(.mediaBox)

  let w = width > 0 ? width : Int(pdfBBox.width)
  let h = height > 0 ? height : Int(pdfBBox.height)

  let fw = fullWidth > 0.0 ? fullWidth : width > 0 ? Double(width) : Double(pdfBBox.width)
  let fh = fullHeight > 0.0 ? fullHeight : height > 0 ? Double(height) : Double(pdfBBox.height)
  let sx = CGFloat(fw) / pdfBBox.width
  let sy = CGFloat(fh) / pdfBBox.height

  let stride = w * 4
  var data = Data(repeating: backgroundFill ? 0xff : 0, count: stride * h)
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
    x: x,
    y: y,
    width: w,
    height: h,
    fullWidth: fw,
    fullHeight: fh,
    pageWidth: Double(pdfBBox.width),
    pageHeight: Double(pdfBBox.height),
    data: data) : nil
}
