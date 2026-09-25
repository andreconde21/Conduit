package com.gwitko.conduit

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.Icon

/**
 * The quick-settings tile icon while Claude's limits are known: two
 * concentric rings, the outer one the 5-hour window, the inner one the
 * week, each a faint track with the used share drawn from 12 o'clock.
 * Tile icons are tinted by the system, so only alpha carries meaning.
 */
object LimitRingsIcon {
    private const val SIZE = 96

    fun create(fiveHourPct: Int?, weekPct: Int?): Icon {
        val bitmap = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val stroke = SIZE * 0.13f
        ring(canvas, inset = stroke / 2 + 2f, stroke = stroke, percent = fiveHourPct)
        ring(canvas, inset = stroke * 1.9f + 2f, stroke = stroke * 0.8f, percent = weekPct)
        return Icon.createWithBitmap(bitmap)
    }

    private fun ring(canvas: Canvas, inset: Float, stroke: Float, percent: Int?) {
        val rect = RectF(inset, inset, SIZE - inset, SIZE - inset)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            color = 0x55FFFFFF
        }
        canvas.drawArc(rect, 0f, 360f, false, paint)
        if (percent == null || percent <= 0) return
        paint.color = 0xFFFFFFFF.toInt()
        canvas.drawArc(rect, -90f, 360f * percent.coerceIn(0, 100) / 100f, false, paint)
    }
}
