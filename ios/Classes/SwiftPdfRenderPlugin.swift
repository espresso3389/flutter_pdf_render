#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import Cocoa
import FlutterMacOS
#endif
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
    let bbox = getBoxRect(.cropBox)
    let rot = rotationAngle
    if rot == 90 || rot == 270 {
        return CGSize(width: bbox.height, height: bbox.width)
    }
    return bbox.size
  }
  func getRotationTransform() -> CGAffineTransform {
    let rect = CGRect(origin: CGPoint.zero, size: getRotatedSize())
    return getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true)
  }
}

enum PdfRenderError : Error {
  case operationFailed(String)
  case invalidArgument(String)
  case notSupported(String)
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
#if os(iOS)
    let channel = FlutterMethodChannel(name: "pdf_render", binaryMessenger: registrar.messenger())
#elseif os(macOS)
    let channel = FlutterMethodChannel(name: "pdf_render", binaryMessenger: registrar.messenger)
#endif
    let instance = SwiftPdfRenderPlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      if call.method == "file"
      {
        guard let pdfFilePath = call.arguments as! String? else {
          throw PdfRenderError.invalidArgument("Expect pdfFilePath as String")
        }
        result(try registerNewDoc(openFileDoc(pdfFilePath: pdfFilePath)))
      }
      else if call.method == "asset"
      {
        guard let name = call.arguments as! String? else {
          throw PdfRenderError.invalidArgument("Expect assetName as String")
        }
        result(try registerNewDoc(openAssetDoc(name: name)))
      }
      else if call.method == "data" {
        guard let data = call.arguments as! FlutterStandardTypedData? else {
          throw PdfRenderError.invalidArgument("Expect byte array")
        }
        result(try registerNewDoc(openDataDoc(data: data.data)))
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
          throw PdfRenderError.invalidArgument("Expect docId as NSNumber")
        }
        result(try getInfo(docId: docId.intValue))
      }
      else if call.method == "page"
      {
        guard let args = call.arguments as! NSDictionary? else {
          throw PdfRenderError.invalidArgument("Expect NSDictionary")
        }
        result(openPage(args: args))
      }
      else if call.method == "render"
      {
        guard let args = call.arguments as! NSDictionary? else {
          throw PdfRenderError.invalidArgument("Expect NSDictionary")
        }
        try render(args: args, result: result)
      }
      else if call.method == "releaseBuffer"
      {
        guard let address = call.arguments as! NSNumber? else {
          throw PdfRenderError.invalidArgument("Expect address as NSNumber")
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
          throw PdfRenderError.invalidArgument("Expect textureId as NSNumber")
        }
        releaseTex(texId: texId.int64Value, result: result)
      }
      else if call.method == "updateTex"
      {
        guard let args = call.arguments as! NSDictionary? else {
          throw PdfRenderError.invalidArgument("Expect NSDictionary")
        }
        try updateTex(args: args, result: result)
      }
      else {
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "exception", message: "Internal error", details: "\(error)"))
    }
  }

#if os(iOS)
  static func isMetalAvailable() -> Bool {
    let device = MTLCreateSystemDefaultDevice()
    return device != nil ? true : false
  }
#elseif os(macOS)
  static func isMetalAvailable() -> Bool {
    let devices = MTLCopyAllDevices()
    return devices.count > 0
  }
#endif

  func registerNewDoc(_ doc: CGPDFDocument?) throws -> NSDictionary? {
    guard doc != nil else {
      throw PdfRenderError.invalidArgument("CGPDFDocument is nil")
    }
    let id = SwiftPdfRenderPlugin.newId
    SwiftPdfRenderPlugin.newId = SwiftPdfRenderPlugin.newId + 1
    if SwiftPdfRenderPlugin.newId == SwiftPdfRenderPlugin.invalid.intValue { SwiftPdfRenderPlugin.newId = 0 }
    docMap[id] = Doc(doc: doc!)
    return try getInfo(docId: id)
  }

  func getInfo(docId: Int) throws -> NSDictionary? {
    guard let doc = docMap[docId]?.doc else {
      throw PdfRenderError.invalidArgument("No PdfDocument for \(docId)")
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

  func openDataDoc(data: Data) throws -> CGPDFDocument? {
    guard let datProv = CGDataProvider(data: data as CFData) else {
      throw PdfRenderError.invalidArgument("CGDataProvider initialization failed")
    }
    return CGPDFDocument(datProv)
  }

  func openAssetDoc(name: String) throws -> CGPDFDocument? {
#if os(iOS)
    let key = registrar.lookupKey(forAsset: name)
    guard let path = Bundle.main.path(forResource: key, ofType: "") else {
      throw PdfRenderError.invalidArgument("Bundle.main.path(forResource: \(key)) failed")
    }
    return openFileDoc(pdfFilePath: path)
#else
    // [macOS] add lookupKeyForAsset to FlutterPluginRegistrar
    // https://github.com/flutter/flutter/issues/47681
    throw PdfRenderError.notSupported("Flutter macos does not support loading asset from plugin")
#endif
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

  func render(args: NSDictionary, result: @escaping FlutterResult) throws {
    let docId = args["docId"] as! Int
    guard let doc = docMap[docId] else {
      throw PdfRenderError.invalidArgument("No PdfDocument for \(docId)")
    }
    let pageNumber = args["pageNumber"] as! Int
    guard pageNumber >= 1 && pageNumber <= doc.pages.count else {
      throw PdfRenderError.invalidArgument("Page number (\(pageNumber)) out of range [1 \(doc.pages.count)]")
    }
    guard let page = doc.pages[pageNumber - 1] else {
      throw PdfRenderError.invalidArgument("Page load failed: pageNumber=\(pageNumber)")
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
      var dict: [String: Any?]? = nil
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
      if dict == nil {
        result(FlutterError(code: "exception", message: "Internal error", details: "renderPdfPageRgba failed"))
      }
      DispatchQueue.main.async {
        // FIXME: Should we use FlutterBasicMessageChannel<ByteData>?
        result(dict! as NSDictionary)
      }
    }
  }

  func releaseBuffer(address: Int, result: @escaping FlutterResult) {
    free(UnsafeMutableRawPointer(bitPattern: address))
    result(nil)
  }

  func allocTex() -> Int64 {
    let pageTex = PdfPageTexture(registrar: registrar)
#if os(iOS)
    let texId = registrar.textures().register(pageTex)
#elseif os(macOS)
    let texId = registrar.textures.register(pageTex)
#endif
    textures[texId] = pageTex
    pageTex.texId = texId
    return texId
  }

  func releaseTex(texId: Int64, result: @escaping FlutterResult) {
#if os(iOS)
    registrar.textures().unregisterTexture(texId)
#elseif os(macOS)
    registrar.textures.unregisterTexture(texId)
#endif
    textures[texId] = nil
    result(nil)
  }

  func updateTex(args: NSDictionary, result: @escaping FlutterResult) throws {
    let texId = args["texId"] as! Int64
    guard let pageTex = textures[texId] else {
      throw PdfRenderError.invalidArgument("No texture of texId=\(texId)")
    }
    let docId = args["docId"] as! Int
    guard let doc = docMap[docId] else {
      throw PdfRenderError.invalidArgument("No document instance of docId=\(docId)")
    }
    let pageNumber = args["pageNumber"] as! Int
    guard pageNumber >= 1 && pageNumber <= doc.pages.count else {
      throw PdfRenderError.invalidArgument("Page number (\(pageNumber)) out of range [1 \(doc.pages.count)]")
    }
    guard let page = doc.pages[pageNumber - 1] else {
      throw PdfRenderError.invalidArgument("Page load failed: pageNumber=\(pageNumber)")
    }

    let width = args["width"] as? Int
    let height = args["height"] as? Int
    let srcX = args["srcX"] as? Int ?? 0
    let srcY = args["srcY"] as? Int ?? 0
    let fw = args["fullWidth"] as? Double
    let fh = args["fullHeight"] as? Double
    let backgroundFill = args["backgroundFill"] as? Bool ?? true
    let allowAntialiasing = args["allowAntialiasingIOS"] as? Bool ?? true

    if width == nil || height == nil {
      throw PdfRenderError.invalidArgument("width/height nil")
    }

    try pageTex.updateTex(page: page, width: width!, height: height!, srcX: srcX, srcY: srcY, fullWidth: fw, fullHeight: fh, backgroundFill: backgroundFill, allowAntialiasing: allowAntialiasing)
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
  var pixBuf : CVPixelBuffer?
  weak var registrar: FlutterPluginRegistrar?
  var texId: Int64 = 0

  init(registrar: FlutterPluginRegistrar?) {
    self.registrar = registrar
  }

  func updateTex(page: CGPDFPage, width: Int, height: Int, srcX: Int, srcY: Int, fullWidth: Double?, fullHeight: Double?, backgroundFill: Bool = false, allowAntialiasing: Bool = true) throws {

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
    let cvRet = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, options as CFDictionary?, &pixBuf)
    if pixBuf == nil {
      throw PdfRenderError.operationFailed("CVPixelBufferCreate failed: result code=\(cvRet)")
    }

    let lockFlags = CVPixelBufferLockFlags(rawValue: 0)
    let _ = CVPixelBufferLockBaseAddress(pixBuf!, lockFlags)
    defer {
      CVPixelBufferUnlockBaseAddress(pixBuf!, lockFlags)
    }

    let bufferAddress = CVPixelBufferGetBaseAddress(pixBuf!)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixBuf!)
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: bufferAddress,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: bytesPerRow,
                            space: rgbColorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

    if backgroundFill {
#if os(iOS)
      context?.setFillColor(UIColor.white.cgColor)
#elseif os(macOS)
      context?.setFillColor(CGColor.white)
#endif
      context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    context?.setAllowsAntialiasing(allowAntialiasing)

    context?.translateBy(x: CGFloat(-srcX), y: CGFloat(Double(srcY + height) - fh))
    context?.scaleBy(x: sx, y: sy)
    context?.concatenate(page.getRotationTransform())
    context?.drawPDFPage(page)
    context?.flush()

    self.pixBuf = pixBuf
#if os(iOS)
    registrar?.textures().textureFrameAvailable(texId)
#elseif os(macOS)
    registrar?.textures.textureFrameAvailable(texId)
#endif
  }
}

extension PdfPageTexture : FlutterTexture {
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    return pixBuf != nil ? Unmanaged<CVPixelBuffer>.passRetained(pixBuf!) : nil
  }
}
