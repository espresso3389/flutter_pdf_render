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

extension CGPDFPage {
  func getRotatedSize() -> CGSize {
    let bbox = getBoxRect(.mediaBox)
    let rot = rotationAngle
    if rot == 90 || rot == 270 {
        return CGSize(width: bbox.height, height: bbox.width)
    }
    return bbox.size
  }
  func getRotationTransform() -> CGAffineTransform {
    let rect = CGRect(origin: CGPoint.zero, size: getRotatedSize())
    return getDrawingTransform(.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true)
  }
}

public class SwiftPdfRenderPlugin: NSObject, FlutterPlugin {
  static let invalid = NSNumber(value: -1)
  let dispQueue = DispatchQueue(label: "pdf_render")
  let registrar: FlutterPluginRegistrar
  static var newId = 0
  var docMap: [Int: Doc] = [:]
  var textures: [Int64: PdfPageTexture] = [:]

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
    }
    else if call.method == "releaseBuffer"
    {
      guard let address = call.arguments as! NSNumber? else {
        result(SwiftPdfRenderPlugin.invalid)
        return
      }

        releaseBuffer(address: address.intValue, result: result)
    }
    else if call.method == "allocTex"
    {
      result(allocTex())
    }
    else if call.method == "releaseTex"
    {
      guard let texId = call.arguments as! NSNumber? else {
        result(SwiftPdfRenderPlugin.invalid)
        return
      }
      releaseTex(texId: texId.int64Value, result: result)
    }
    else if call.method == "resizeTex"
    {
      guard let args = call.arguments as! NSDictionary? else {
        result(SwiftPdfRenderPlugin.invalid)
        return
      }
      resizeTex(args: args, result: result)
    }
    else if call.method == "updateTex"
    {
      guard let args = call.arguments as! NSDictionary? else {
        result(SwiftPdfRenderPlugin.invalid)
        return
      }
      updateTex(args: args, result: result)
    }
    else {
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

    let rotatedSize = page!.getRotatedSize()
    let dict: [String: Any] = [
      "docId": Int32(docId),
      "pageNumber": Int32(pageNumber),
      "width": NSNumber(value: Double(rotatedSize.width)),
      "height": NSNumber(value: Double(rotatedSize.height))
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

    let x = args["x"] as? Int ?? 0
    let y = args["y"] as? Int ?? 0
    let w = args["width"] as? Int ?? 0
    let h = args["height"] as? Int ?? 0
    let fw = args["fullWidth"] as? Double ?? 0.0
    let fh = args["fullHeight"] as? Double ?? 0.0
    let backgroundFill = args["backgroundFill"] as? Bool ?? true
    let allowAntialiasing = args["allowAntialiasingIOS"] as? Bool ?? true

    dispQueue.async {
      var dict: [String: Any]? = nil
      if let data = renderPdfPageRgba(page: page, x: x, y: y, width: w, height: h, fullWidth: fw, fullHeight: fh, backgroundFill: backgroundFill, allowAntialiasing: allowAntialiasing) {
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
          "data": data.address == 0 ? FlutterStandardTypedData(bytes: data.data) : nil,
          "addr": NSNumber(value: data.address),
          "size": NSNumber(value: data.size)
        ]
      }
      DispatchQueue.main.async {
        // FIXME: Should we use FlutterBasicMessageChannel<ByteData>?
        result(dict != nil ? (dict! as NSDictionary) : nil)
      }
    }
  }

  func releaseBuffer(address: Int, result: @escaping FlutterResult) {
    free(UnsafeMutableRawPointer(bitPattern: address))
    result(nil)
  }

  func allocTex() -> Int64 {
    let pageTex = PdfPageTexture(registrar: registrar)
    let texId = registrar.textures().register(pageTex)
    textures[texId] = pageTex
    pageTex.texId = texId
    return texId
  }

  func releaseTex(texId: Int64, result: @escaping FlutterResult) {
    registrar.textures().unregisterTexture(texId)
    textures[texId] = nil
    result(nil)
  }

  func resizeTex(args: NSDictionary, result: @escaping FlutterResult) {
    let texId = args["texId"] as! Int64
    guard let pageTex = textures[texId] else {
      result(SwiftPdfRenderPlugin.invalid)
      return
    }
    let w = args["width"] as! Int
    let h = args["height"] as! Int
    pageTex.resize(width: w, height: h)
  }

  func updateTex(args: NSDictionary, result: @escaping FlutterResult) {
    let texId = args["texId"] as! Int64
    guard let pageTex = textures[texId] else {
      result(SwiftPdfRenderPlugin.invalid)
      return
    }
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

    let destX = args["destX"] as? Int ?? 0
    let destY = args["destY"] as? Int ?? 0
    let width = args["width"] as? Int
    let height = args["height"] as? Int
    let srcX = args["srcX"] as? Int ?? 0
    let srcY = args["srcY"] as? Int ?? 0
    let fw = args["fullWidth"] as? Double
    let fh = args["fullHeight"] as? Double
    let backgroundFill = args["backgroundFill"] as? Bool ?? true
    let allowAntialiasing = args["allowAntialiasingIOS"] as? Bool ?? true

    let tw = args["texWidth"] as? Int
    let th = args["texHeight"] as? Int
    if tw != nil && th != nil {
      pageTex.resize(width: tw!, height: th!)
    }

    pageTex.updateTex(page: page, destX: destX, destY: destY, width: width, height: height, srcX: srcX, srcY: srcY, fullWidth: fw, fullHeight: fh, backgroundFill: backgroundFill, allowAntialiasing: allowAntialiasing)
    result(0)
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
  let address: Int64
  let size: Int
  init(x: Int, y: Int, width: Int, height: Int, fullWidth: Double, fullHeight: Double, pageWidth: Double, pageHeight: Double, data: Data, address: Int64, size: Int) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.fullWidth = fullWidth
    self.fullHeight = fullHeight
    self.pageWidth = pageWidth
    self.pageHeight = pageHeight
    self.data = data
    self.address = address
    self.size = size
  }
}

func renderPdfPageRgba(page: CGPDFPage, x: Int, y: Int, width: Int, height: Int, fullWidth: Double, fullHeight: Double, backgroundFill: Bool, allowAntialiasing: Bool) -> PageData? {

  let rotatedSize = page.getRotatedSize()

  let w = width > 0 ? width : Int(rotatedSize.width)
  let h = height > 0 ? height : Int(rotatedSize.height)
  let fw = fullWidth > 0.0 ? fullWidth : Double(w)
  let fh = fullHeight > 0.0 ? fullHeight : Double(h)

  let sx = CGFloat(fw) / rotatedSize.width
  let sy = CGFloat(fh) / rotatedSize.height

  let stride = w * 4
  let bufSize = stride * h;
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
    buffer.initialize(repeating: backgroundFill ? 0xff : 0, count: bufSize)
  var success = false

  let rgb = CGColorSpaceCreateDeviceRGB()
  let context = CGContext(data: buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: stride, space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  if context != nil {
    context!.setAllowsAntialiasing(allowAntialiasing);

    context!.translateBy(x: CGFloat(-x), y: CGFloat(Double(y + h) - fh))
    context!.scaleBy(x: sx, y: sy)
    context!.concatenate(page.getRotationTransform())

    context!.drawPDFPage(page)
    success = true
  }
  return success ? PageData(
    x: x,
    y: y,
    width: w,
    height: h,
    fullWidth: fw,
    fullHeight: fh,
    pageWidth: Double(rotatedSize.width),
    pageHeight: Double(rotatedSize.height),
    data: Data(bytesNoCopy: buffer, count: bufSize, deallocator: .none),
    address: Int64(Int(bitPattern: buffer)),
    size: bufSize) : nil
}

class PdfPageTexture : NSObject {
  let pixBuf = AtomicReference<CVPixelBuffer?>(initialValue: nil)
  weak var registrar: FlutterPluginRegistrar?
  var texId: Int64 = 0
  var texWidth: Int = 0
  var texHeight: Int = 0

  init(registrar: FlutterPluginRegistrar?) {
    self.registrar = registrar
  }

  func resize(width: Int, height: Int) {
    if self.texWidth == width && self.texHeight == height {
      return
    }
    self.texWidth = width
    self.texHeight = height
  }

  func updateTex(page: CGPDFPage, destX: Int, destY: Int, width: Int?, height: Int?, srcX: Int, srcY: Int, fullWidth: Double?, fullHeight: Double?, backgroundFill: Bool = false, allowAntialiasing: Bool = true) {

    guard let w = width else { return }
    guard let h = height else { return }

    let rotatedSize = page.getRotatedSize()
    let fw = fullWidth ?? Double(rotatedSize.width)
    let fh = fullHeight ?? Double(rotatedSize.height)
    let sx = CGFloat(fw) / rotatedSize.width
    let sy = CGFloat(fh) / rotatedSize.height

    var pixBuf: CVPixelBuffer?
    let options = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:]
      ] as [String : Any]
    CVPixelBufferCreate(kCFAllocatorDefault, texWidth, texHeight, kCVPixelFormatType_32BGRA, options as CFDictionary?, &pixBuf)

    let lockFlags = CVPixelBufferLockFlags(rawValue: 0)
    let _ = CVPixelBufferLockBaseAddress(pixBuf!, lockFlags)
    defer {
      CVPixelBufferUnlockBaseAddress(pixBuf!, lockFlags)
    }

    let bufferAddress = CVPixelBufferGetBaseAddress(pixBuf!)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixBuf!)
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: bufferAddress?.advanced(by: destX * 4 + destY * bytesPerRow),
                            width: w,
                            height: h,
                            bitsPerComponent: 8,
                            bytesPerRow: bytesPerRow,
                            space: rgbColorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

    if backgroundFill {
      context?.setFillColor(UIColor.white.cgColor)
      context?.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }

    context?.setAllowsAntialiasing(allowAntialiasing)

    context?.translateBy(x: CGFloat(-srcX), y: CGFloat(Double(srcY + h) - fh))
    context?.scaleBy(x: sx, y: sy)
    context?.concatenate(page.getRotationTransform())
    context?.drawPDFPage(page)
    context?.flush()

    let _ = self.pixBuf.getAndSet(newValue: pixBuf)
    registrar?.textures().textureFrameAvailable(texId)
  }
}

extension PdfPageTexture : FlutterTexture {
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    let val = pixBuf.getAndSet(newValue: nil)
    return val != nil ? Unmanaged<CVPixelBuffer>.passRetained(val!) : nil
  }
}
