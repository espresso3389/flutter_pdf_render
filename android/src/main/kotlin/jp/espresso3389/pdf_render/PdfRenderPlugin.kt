package jp.espresso3389.pdf_render

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.pdf.PdfRenderer
import android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY
import android.os.ParcelFileDescriptor
import android.os.ParcelFileDescriptor.MODE_READ_ONLY
//import android.util.Log
import android.util.SparseArray
import android.view.Surface
import androidx.annotation.NonNull
import androidx.collection.LongSparseArray
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar
import io.flutter.view.TextureRegistry
import java.io.File
import java.io.OutputStream
import java.nio.Buffer
import java.nio.ByteBuffer

/** PdfRenderPlugin */
class PdfRenderPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding

  private val documents: SparseArray<PdfRenderer> = SparseArray()
  private var lastDocId: Int = 0
  private val textures: SparseArray<TextureRegistry.SurfaceTextureEntry> = SparseArray()

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    this.flutterPluginBinding = flutterPluginBinding
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "pdf_render")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    try {
      when {
        call.method == "file" -> {
          val pdfFilePath = call.arguments as String
          result.success(registerNewDoc(openFileDoc(call.arguments as String)))
        }
        call.method == "asset" -> {
          result.success(registerNewDoc(openAssetDoc(call.arguments as String)))
        }
        call.method == "data" -> {
          result.success(registerNewDoc(openDataDoc(call.arguments as ByteArray)))
        }
        call.method == "close" -> {
          close(call.arguments as Int)
          result.success(0)
        }
        call.method == "info" -> {
          val (renderer, id) = getDoc(call)
          result.success(getInfo(renderer, id))
        }
        call.method == "page" -> {
          result.success(openPage(call.arguments as HashMap<String, Any>))
        }
        call.method == "render" -> {
          render(call.arguments as HashMap<String, Any>, result)
        }
        call.method == "releaseBuffer" -> {
          releaseBuffer(call.arguments as Long)
          result.success(0)
        }
        call.method == "allocTex" -> {
          result.success(allocTex())
        }
        call.method == "releaseTex" -> {
          releaseTex(call.arguments as Int)
          result.success(0)
        }
        call.method == "updateTex" -> {
          result.success(updateTex(call.arguments as HashMap<String, Any>))
        }
        else -> result.notImplemented()
      }
    } catch (e: Exception) {
      result.error("exception", "Internal error.", e)
    }
  }

  private fun registerNewDoc(pdfRenderer: PdfRenderer): HashMap<String, Any> {
    val id = ++lastDocId
    documents.put(id, pdfRenderer)
    return getInfo(pdfRenderer, id)
  }

  private fun getDoc(call: MethodCall): Pair<PdfRenderer, Int> {
    val id = call.arguments as Int
    return Pair(documents[id], id)
  }

  private fun getInfo(pdfRenderer: PdfRenderer, id: Int): HashMap<String, Any> {
    return hashMapOf(
      "docId" to id,
      "pageCount" to pdfRenderer.pageCount,
      "verMajor" to 1,
      "verMinor" to 7,
      "isEncrypted" to false,
      "allowsCopying" to false,
      "allowsPrinting" to false)
  }

  private fun close(id: Int) {
    val renderer = documents[id]
    if (renderer != null) {
      renderer.close()
      documents.remove(id)
    }
  }

  private fun openFileDoc(pdfFilePath: String): PdfRenderer {
    val fd = ParcelFileDescriptor.open(File(pdfFilePath), MODE_READ_ONLY)
    return PdfRenderer(fd)
  }

  private fun copyToTempFileAndOpenDoc(writeData: (OutputStream) -> Unit): PdfRenderer {
    val file = File.createTempFile("pdfr", null, null)
    try {
      file.outputStream().use {
        writeData(it)
      }
      file.inputStream().use {
        return PdfRenderer(ParcelFileDescriptor.dup(it.fd))
      }
    } finally {
      file.delete()
    }
  }

  private fun openAssetDoc(pdfAssetName: String): PdfRenderer {
    val key = flutterPluginBinding.flutterAssets.getAssetFilePathByName(pdfAssetName)
    // NOTE: the input stream obtained from asset may not be
    // a file stream and we should convert it to file
    flutterPluginBinding.applicationContext.assets.open(key).use { input ->
      return copyToTempFileAndOpenDoc { input.copyTo(it) }
    }
  }

  private fun openDataDoc(data: ByteArray): PdfRenderer {
    return copyToTempFileAndOpenDoc { it.write(data) }
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
        "width" to it.width.toDouble(),
        "height" to it.height.toDouble()
      )
    }
  }

  private fun renderOnByteBuffer(args: HashMap<String, Any>, createBuffer: (Int) -> ByteBuffer): HashMap<String, Any?>? {
    val docId = args["docId"] as Int
    val renderer = documents[docId]
    val pageNumber = args["pageNumber"] as Int
    renderer.openPage(pageNumber - 1).use {
      val x = args["x"] as? Int? ?: 0
      val y = args["y"] as? Int? ?: 0
      val _w = args["width"] as? Int? ?: 0
      val _h = args["height"] as? Int? ?: 0
      val w = if (_w > 0) _w else it.width
      val h = if (_h > 0) _h else it.height
      val _fw = args["fullWidth"] as? Double ?: 0.0
      val _fh = args["fullHeight"] as? Double ?: 0.0
      val fw = if (_fw > 0) _fw.toFloat() else w.toFloat()
      val fh = if (_fh > 0) _fh.toFloat() else h.toFloat()
      val backgroundFill = args["backgroundFill"] as? Boolean ?: true

      val buf = createBuffer(w * h * 4)

      val mat = Matrix()
      mat.setValues(floatArrayOf(fw / it.width, 0f, -x.toFloat(), 0f, fh / it.height, -y.toFloat(), 0f, 0f, 1f))

      val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)

      if (backgroundFill) {
        bmp.eraseColor(Color.WHITE)
      }

      it.render(bmp, null, mat, RENDER_MODE_FOR_DISPLAY)

      bmp.copyPixelsToBuffer(buf)
      bmp.recycle()

      return hashMapOf(
        "docId" to docId,
        "pageNumber" to pageNumber,
        "x" to x,
        "y" to y,
        "width" to w,
        "height" to h,
        "fullWidth" to fw.toDouble(),
        "fullHeight" to fh.toDouble(),
        "pageWidth" to it.width.toDouble(),
        "pageHeight" to it.height.toDouble()
      )
    }
  }

  private fun render(args: HashMap<String, Any>, result: Result) {
    var buf: ByteBuffer? = null
    var addr: Long = 0L
    val m = renderOnByteBuffer(args) {
      val (addr_, bbuf) = allocBuffer(it)
      buf = bbuf
      addr = addr_
      return@renderOnByteBuffer bbuf
    }
    if (addr != 0L) {
      m?.set("addr", addr)
    } else {
      m?.set("data", buf?.array())
    }
    m?.set("size", buf?.capacity())
    result.success(m)
  }

  private fun allocBuffer(size: Int): Pair<Long, ByteBuffer> {
    val addr = ByteBufferHelper.malloc(size.toLong())
    val bb = ByteBufferHelper.newDirectBuffer(addr, size.toLong())
    return addr to bb
  }

  private fun releaseBuffer(addr: Long) {
    ByteBufferHelper.free(addr)
  }

  private fun allocTex(): Int {
    val surfaceTexture = flutterPluginBinding.textureRegistry.createSurfaceTexture()
    val id = surfaceTexture.id().toInt()
    textures.put(id, surfaceTexture)
    return id
  }

  private fun releaseTex(texId: Int) {
    val tex = textures[texId]
    tex?.release()
    textures.remove(texId)
  }

  private fun updateTex(args: HashMap<String, Any>): Int {
    val texId = args["texId"] as Int
    val docId = args["docId"] as Int
    val pageNumber = args["pageNumber"] as Int
    val tex = textures[texId]
    if (tex == null) return -8

    val renderer = documents[docId]

    renderer.openPage(pageNumber - 1). use {page ->
      val fullWidth = args["fullWidth"] as? Double ?: page.width.toDouble()
      val fullHeight = args["fullHeight"] as? Double ?: page.height.toDouble()
      val width = args["width"] as? Int ?: 0
      val height = args["height"] as? Int ?: 0
      val srcX = args["srcX"] as? Int ?: 0
      val srcY = args["srcY"] as? Int ?: 0
      val backgroundFill = args["backgroundFill"] as? Boolean ?: true

      if (width <= 0 || height <= 0)
        return -7

      val mat = Matrix()
      mat.setValues(floatArrayOf((fullWidth / page.width).toFloat(), 0f, -srcX.toFloat(), 0f, (fullHeight / page.height).toFloat(), -srcY.toFloat(), 0f, 0f, 1f))

      val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
      if (backgroundFill) {
        bmp.eraseColor(Color.WHITE)
      }
      page.render(bmp, null, mat, RENDER_MODE_FOR_DISPLAY)

      tex.surfaceTexture()?.setDefaultBufferSize(width, height)

      Surface(tex.surfaceTexture()).use {
        val canvas = it.lockCanvas(Rect(0, 0, width, height));

        canvas.drawBitmap(bmp, 0f, 0f, null)
        bmp.recycle()

        it.unlockCanvasAndPost(canvas)
      }
    }
    return 0
  }
}

fun <R> Surface.use(block: (Surface) -> R): R {
  try {
    return block(this)
  }
  finally {
    this.release()
  }
}
