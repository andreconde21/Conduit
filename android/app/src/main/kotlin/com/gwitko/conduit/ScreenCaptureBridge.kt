package com.gwitko.conduit

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.PixelCopy
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Copies a region of the app window into a PNG for Live preview's
 * "Screenshot to Claude". The WebView is a platform view, which Flutter's
 * own `toImage` cannot read; PixelCopy reads what the compositor shows.
 *
 * Method channel (`conduit/screen_capture`):
 *  - `capture` {left, top, width, height} in window pixels -> PNG bytes.
 *    Fails with `unsupported` below Android 8 (PixelCopy on a Window needs
 *    API 26), so Dart falls back to its own capture.
 */
class ScreenCaptureBridge(private val activity: Activity) {
    companion object {
        const val CHANNEL = "conduit/screen_capture"
    }

    private val encoder = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capture" -> capture(call, result)
            else -> result.notImplemented()
        }
    }

    private fun capture(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("unsupported", "PixelCopy needs Android 8", null)
            return
        }
        val window = activity.window
        val decor = window?.decorView
        if (window == null || decor == null) {
            result.error("no_window", "The activity has no window", null)
            return
        }
        val left = (call.argument<Int>("left") ?: 0).coerceIn(0, decor.width)
        val top = (call.argument<Int>("top") ?: 0).coerceIn(0, decor.height)
        val right = (left + (call.argument<Int>("width") ?: 0)).coerceAtMost(decor.width)
        val bottom = (top + (call.argument<Int>("height") ?: 0)).coerceAtMost(decor.height)
        if (right <= left || bottom <= top) {
            result.error("empty", "Nothing to capture", null)
            return
        }
        val bitmap = Bitmap.createBitmap(right - left, bottom - top, Bitmap.Config.ARGB_8888)
        val thread = HandlerThread("conduit-pixelcopy").apply { start() }
        try {
            PixelCopy.request(
                window,
                Rect(left, top, right, bottom),
                bitmap,
                { status ->
                    thread.quitSafely()
                    if (status != PixelCopy.SUCCESS) {
                        bitmap.recycle()
                        mainHandler.post { result.error("copy_failed", "PixelCopy status $status", null) }
                        return@request
                    }
                    encoder.execute {
                        val out = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                        bitmap.recycle()
                        val bytes = out.toByteArray()
                        mainHandler.post { result.success(bytes) }
                    }
                },
                Handler(thread.looper),
            )
        } catch (error: IllegalArgumentException) {
            thread.quitSafely()
            bitmap.recycle()
            result.error("copy_failed", error.message, null)
        }
    }
}
