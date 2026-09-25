package com.gwitko.conduit

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Reads an image from the system clipboard for the Chat composer's
 * "Paste image" (Flutter's Clipboard API is text-only).
 *
 * The clip's content URI is only readable while it is on the clipboard, so
 * the stream is copied into `cacheDir/prompt-images/<id>/clipboard.<ext>`
 * on a worker thread and Dart receives the plain file path.
 *
 * Method channel (`conduit/clipboard_image`):
 *  - `readImage` -> {path, name, size, mimeType} or null when the clipboard
 *    holds no image.
 *  - `hasImage` -> whether it holds one, without copying anything (for
 *    offering "Paste image").
 */
class ClipboardImageBridge(private val context: Context) {
    companion object {
        const val CHANNEL = "conduit/clipboard_image"
        private const val MAX_BYTES = 50L * 1024 * 1024
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readImage" -> readImage(result)
            "hasImage" -> result.success(imageUri() != null)
            else -> result.notImplemented()
        }
    }

    private fun readImage(result: MethodChannel.Result) {
        val uri = imageUri()
        if (uri == null) {
            result.success(null)
            return
        }
        executor.execute {
            val copied = try {
                copyToCache(uri)
            } catch (_: Exception) {
                null
            }
            mainHandler.post { result.success(copied) }
        }
    }

    private fun imageUri(): Uri? {
        val clipboard =
            context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                ?: return null
        val clip = clipboard.primaryClip ?: return null
        for (index in 0 until clip.itemCount) {
            val uri = clip.getItemAt(index).uri ?: continue
            val type = context.contentResolver.getType(uri)
                ?: if (clip.description.hasMimeType("image/*")) "image/*" else null
            if (type != null && type.startsWith("image/")) {
                return uri
            }
        }
        return null
    }

    private fun copyToCache(uri: Uri): Map<String, Any?>? {
        val mimeType = context.contentResolver.getType(uri) ?: "image/png"
        val extension = MimeTypeMap.getSingleton()
            .getExtensionFromMimeType(mimeType) ?: "png"
        val dir = File(File(context.cacheDir, "prompt-images"), UUID.randomUUID().toString())
        dir.mkdirs()
        val target = File(dir, "clipboard.$extension")
        var copied = 0L
        context.contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    copied += read
                    if (copied > MAX_BYTES) {
                        throw IllegalStateException("clipboard image too large")
                    }
                    output.write(buffer, 0, read)
                }
            }
        } ?: return null
        return mapOf(
            "path" to target.absolutePath,
            "name" to target.name,
            "size" to copied,
            "mimeType" to mimeType,
        )
    }
}
