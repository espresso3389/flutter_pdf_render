package jp.espresso3389.pdfrender

import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY
import android.os.ParcelFileDescriptor
import android.os.ParcelFileDescriptor.MODE_READ_ONLY
import android.os.SharedMemory
import android.util.SparseArray
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.PluginRegistry.Registrar
import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer

class PdfRenderPlugin(registrar: Registrar): MethodCallHandler {
  companion object {
    @JvmStatic
    fun registerWith(registrar: Registrar): Unit {
      val channel = MethodChannel(registrar.messenger(), "pdf_render")
      channel.setMethodCallHandler(PdfRenderPlugin(registrar))
    }
  }

  private val registrar: Registrar = registrar
  private val documents: SparseArray<PdfRenderer> = SparseArray()
  private var lastId: Int = 0

  override fun onMethodCall(call: MethodCall, result: Result): Unit {
    try {
      when {
        call.method == "file" -> {
          val pdfFilePath = call.arguments as? String
          if (pdfFilePath == null) {
            result.success(null)
            return
          }
          result.success(registerNewDoc(openFileDoc(pdfFilePath)))
        }
        call.method == "asset" -> {
          val pdfAssetName = call.arguments as? String
          if (pdfAssetName == null) {
            result.success(null)
            return
          }
          result.success(registerNewDoc(openAssetDoc(pdfAssetName)))
        }
        call.method == "data" -> {
          val data = call.arguments as? ByteArray
          if (data == null) {
            result.success(null)
            return
          }
          result.success(registerNewDoc(openDataDoc(data)))
        }
        call.method == "close" -> {
          val id = call.arguments as? Int
          if (id != null)
            close(id)
          result.success(0)
        }
        call.method == "info" -> {
          val (renderer, id) = getDoc(call)
          if (renderer == null) {
            result.success(-1)
            return
          }
          result.success(getInfo(renderer, id))
        }
        call.method == "page" -> {
          val args = call.arguments as? HashMap<String, Any>
          if (args == null) {
            result.success(null)
            return
          }
          result.success(openPage(args))
        }
        call.method == "render" -> {
          val args = call.arguments as? HashMap<String, Any>
          if (args == null) {
            result.success(-1)
            return
          }
          result.success(render(args, result))
        }
        else -> result.notImplemented()
      }
    } catch (e: Exception) {
      result.error("exception", "Internal error.", e)
    }
  }

  private fun registerNewDoc(pdfRenderer: PdfRenderer): HashMap<String, Any> {
    val id = ++lastId
    documents.put(id, pdfRenderer)
    return getInfo(pdfRenderer, id)
  }

  private fun getDoc(call: MethodCall): Pair<PdfRenderer?, Int> {
    val id = call.arguments as? Int
    if (id != null)
      return Pair(documents[id], id)
    return Pair(null, -1)
  }

  private fun getInfo(pdfRenderer: PdfRenderer, id: Int): HashMap<String, Any> {
    return hashMapOf(
            "docId" to id,
            "pageCount" to pdfRenderer.pageCount,
            "verMajor" to 1,
            "verMinor" to 7,
            "isEncrypted" to false,
            "allowsCopying" to false,
            "allowPrinting" to false)
  }

  private fun close(id: Int) {
    val renderer = documents[id]
    if (renderer != null) {
      renderer.close()
      documents.removeAt(id)
    }
  }

  private fun openFileDoc(pdfFilePath: String): PdfRenderer {
    val fd = ParcelFileDescriptor.open(File(pdfFilePath), MODE_READ_ONLY)
    return PdfRenderer(fd)
  }

  /**
   * Copy input stream to temporary file to enable pure file access.
   */
  private fun copyToTempFileAndOpenDoc(input: InputStream): PdfRenderer {
    val file = File.createTempFile("pdfr", null, null)
    try {
      file.outputStream().use { output ->
        input.copyTo(output)
      }
      file.inputStream().use {
        return PdfRenderer(ParcelFileDescriptor.dup(it.fd))
      }
    } finally {
      file.delete()
    }
  }

  private fun openAssetDoc(pdfAssetName: String): PdfRenderer {
    val key = registrar.lookupKeyForAsset(pdfAssetName)
    // NOTE: the input stream obtained from asset may not be
    // a file stream and we should convert it to file
    registrar.context().assets.open(key).use { input ->
      return copyToTempFileAndOpenDoc(input)
    }
  }

  private fun openDataDoc(data: ByteArray): PdfRenderer {
    //return PdfRenderer(ParcelFileDescriptor.fromData(data, null))
    throw NotImplementedError()
  }

  private fun openPage(args: HashMap<String, Any>): HashMap<String, Any>? {
    val docId = args["docId"] as? Int ?: return null
    val renderer = documents[docId] ?: return null
    val pageNumber = args["pageNumber"] as? Int ?: return null
    if (pageNumber < 1 || pageNumber > renderer.pageCount) return null
    renderer.openPage(pageNumber - 1).use {
      return hashMapOf(
              "docId" to docId,
              "pageNumber" to pageNumber,
              "rotationAngle" to 0, // FIXME: no rotation angle can be obtained
              "width" to it.width.toDouble(),
              "height" to it.height.toDouble()
      )
    }
  }

  private fun render(args: HashMap<String, Any>, result: Result) {
    val docId = args["docId"] as? Int
    val renderer = if (docId != null) documents[docId] else null
    val pageNumber = args["pageNumber"] as? Int
    if (renderer == null || pageNumber == null || pageNumber < 1 || pageNumber > renderer.pageCount) {
      result.success(-1)
      return
    }
    val x = args["x"] as? Int ?: 0
    val y = args["y"] as? Int ?: 0
    val w = args["width"] as? Int ?: 0
    val h = args["height"] as? Int ?: 0
    val _fw = args["fullWidth"]
    val _fh = args["fullHeight"]
    val fw = if (_fw is Int && _fw != 0) _fw.toFloat() else w.toFloat()
    val fh = if (_fh is Int && _fh != 0) _fh.toFloat() else h.toFloat()


    val buf = ByteBuffer.allocate(w * h * 4)
    renderer.openPage(pageNumber - 1).use {
      val mat = Matrix()
      mat.setValues(floatArrayOf(fw / it.width, 0f, -x.toFloat(), 0f, fh / it.height, -y.toFloat(), 0f, 0f, 1f))

      val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
      it.render(bmp, null, mat, RENDER_MODE_FOR_DISPLAY)

      bmp.copyPixelsToBuffer(buf)

      result.success(hashMapOf(
              "docId" to docId,
              "pageNumber" to pageNumber,
              "x" to x,
              "y" to y,
              "width" to w,
              "height" to h,
              "fullWidth" to fw.toDouble(),
              "fullHeight" to fh.toDouble(),
              "pageWidth" to it.width.toDouble(),
              "pageHeight" to it.height.toDouble(),
              "data" to buf.array()
      ))
    }
  }
}
