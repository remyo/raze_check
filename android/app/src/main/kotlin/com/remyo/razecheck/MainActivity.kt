package com.remyo.razecheck

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.Executors

// No allocation from provider-controlled metadata; also used for unknown sizes.
internal fun boundedCopy(input: InputStream, target: File, limit: Long, reportedSize: Long? = null) {
    try {
        input.use { source ->
          if (reportedSize != null && reportedSize > limit) throw TransferLimitException()
          target.outputStream().use { output ->
            val buffer = ByteArray(32768)
            var count = 0L
            while (true) {
                val n = source.read(buffer)
                if (n < 0) break
                if (n == 0) continue
                count += n
                if (count > limit) throw TransferLimitException()
                output.write(buffer, 0, n)
            }
        } }
    } catch (e: Exception) { target.delete(); throw e }
}
internal class TransferLimitException : Exception()

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var limit = 65536L
    private val io = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.remyo.razecheck/documents")
            .setMethodCallHandler { call, result ->
                if (call.method != "pick") { result.notImplemented(); return@setMethodCallHandler }
                if (pending != null) { result.error("busy", "A document is already open", null); return@setMethodCallHandler }
                val purpose = call.argument<String>("purpose")
                limit = when (purpose) { "message" -> 65536L; "image" -> 20L*1024*1024; "archive" -> 64L*1024*1024; else -> { result.error("invalidPurpose", "Invalid purpose", null); return@setMethodCallHandler } }
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = if (purpose == "image") "image/*" else "*/*"
                    if (purpose == "image") putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/png", "image/jpeg"))
                    // Custom .razecheck-message is not a registered MIME. Broad
                    // data fallback keeps Files usable; Dart validates wire data.
                }
                pending = result
                try { startActivityForResult(intent, 9421) }
                catch (_: Exception) { pending=null; result.error("unavailable", "Files unavailable", null) }
            }
    }
    @Deprecated("Activity result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 9421) return
        val result = pending ?: return
        if (resultCode == Activity.RESULT_CANCELED) { pending=null; result.success(null); return }
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { pending=null; result.error("unavailable", "File unavailable", null); return }
        val max = limit
        io.execute {
            val dir = File(cacheDir, "raze-document-staging").apply { mkdirs() }
            dir.listFiles()?.filter { it.isFile && System.currentTimeMillis()-it.lastModified()>86400000 }?.forEach { it.delete() }
            val target = File(dir, UUID.randomUUID().toString())
            try {
                val size = try { contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { c ->
                    if (c.moveToFirst() && !c.isNull(0)) c.getLong(0) else null
                } } catch (_: Exception) { null }
                if (size != null && size > max) throw TransferLimitException()
                val input = contentResolver.openInputStream(uri) ?: throw java.io.IOException()
                boundedCopy(input, target, max, size)
                runOnUiThread { pending=null; result.success(target.absolutePath) }
            } catch (e: Exception) {
                target.delete()
                runOnUiThread { pending=null; result.error(if (e is TransferLimitException) "limitExceeded" else "unavailable", "Save locally and retry", null) }
            }
        }
    }
}
