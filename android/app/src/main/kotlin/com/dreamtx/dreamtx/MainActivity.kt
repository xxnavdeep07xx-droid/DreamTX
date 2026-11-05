package com.dreamtx.dreamtx

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "dreamtx/files"
        const val REQUEST_PICK_DOCUMENT = 4201
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickDocument" -> openDocumentPicker(result)
                    "getFilesDirectory" -> result.success(filesDir.absolutePath)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        pendingResult?.error("ACTIVITY_DESTROYED", "Activity destroyed before result", null)
        pendingResult = null
        super.onDestroy()
    }

    private fun openDocumentPicker(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("PICK_IN_PROGRESS", "A file selection is already in progress", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "application/pdf",
                    "application/msword",
                    "application/vnd.ms-powerpoint",
                    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                    "application/vnd.openxmlformats-officedocument.presentationml.presentation"
                )
            )
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_PICK_DOCUMENT)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_DOCUMENT) return
        val result = pendingResult ?: return
        pendingResult = null
        if (resultCode == Activity.RESULT_OK && data?.data != null) {
            result.success(readFileInfo(data.data!!))
        } else {
            // User cancelled.
            result.success(null)
        }
    }

    private fun readFileInfo(uri: Uri): Map<String, Any?> {
        var name = "Document"
        var size: Int? = null
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) cursor.getString(nameIndex)?.let { name = it }
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    size = cursor.getInt(sizeIndex)
                }
            }
        }
        return mapOf("uri" to uri.toString(), "name" to name, "size" to size)
    }
}
