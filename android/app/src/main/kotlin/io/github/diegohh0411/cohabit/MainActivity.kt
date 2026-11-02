package io.github.diegohh0411.cohabit

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val CREATE_DOCUMENT = 4201

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cohabit/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveDocument") {
                    result.notImplemented()
                } else if (pendingResult != null) {
                    result.error("busy", "A save is already open", null)
                } else {
                    pendingResult = result
                    pendingBytes = call.argument<ByteArray>("bytes")
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType(call.argument<String>("mimeType"))
                        .putExtra(Intent.EXTRA_TITLE, call.argument<String>("fileName"))
                    startActivityForResult(intent, CREATE_DOCUMENT)
                }
            }
    }

    @Deprecated("Required by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CREATE_DOCUMENT) return
        val result = pendingResult ?: return
        val bytes = pendingBytes
        pendingResult = null
        pendingBytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) {
            result.success(false)
            return
        }
        Thread {
            val failure = runCatching { writeAndVerify(uri, bytes) }.exceptionOrNull()
            if (failure != null) {
                runCatching { DocumentsContract.deleteDocument(contentResolver, uri) }
            }
            runOnUiThread {
                if (failure == null) {
                    result.success(true)
                } else {
                    result.error("write_failed", "Could not save the file", null)
                }
            }
        }.start()
    }

    /** Providers can accept a document and store nothing, so read it back. */
    private fun writeAndVerify(uri: Uri, bytes: ByteArray) {
        val output = contentResolver.openOutputStream(uri)
            ?: error("No output stream")
        output.use { it.write(bytes) }
        val written = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: error("No input stream")
        check(written.contentEquals(bytes)) { "Saved file differs" }
    }
}
