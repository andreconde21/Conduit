package com.gwitko.conduit

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.text.format.DateFormat
import android.view.View
import android.widget.RemoteViews
import java.util.Date

/**
 * Home-screen widget: attention count, up to four agents (most urgent
 * first) and the time of the last snapshot. Tapping anywhere opens the app
 * on the agent attention sheet.
 */
class AgentStatusWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val snapshot = AgentStatusStore.load(context)
        for (id in ids) {
            manager.updateAppWidget(id, build(context, snapshot, manager.getAppWidgetOptions(id)))
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) {
        manager.updateAppWidget(id, build(context, AgentStatusStore.load(context), options))
    }

    companion object {
        private val rowIds = intArrayOf(
            R.id.widget_agent_1,
            R.id.widget_agent_2,
            R.id.widget_agent_3,
            R.id.widget_agent_4,
        )

        /** Below this height (dp) only the count and the top agent fit. */
        private const val COMPACT_MAX_HEIGHT_DP = 100

        /** Below this width (dp) only the 5-hour ring fits beside the title. */
        private const val NARROW_MAX_WIDTH_DP = 180

        /** A limit ring: its frame, label, one bar per colour level and the percentage. */
        private class Ring(
            val label: String,
            val frame: Int,
            val caption: Int,
            val normal: Int,
            val warning: Int,
            val critical: Int,
            val text: Int,
        )

        private val rings = listOf(
            Ring(
                "5h",
                R.id.widget_ring_5h,
                R.id.widget_ring_5h_label,
                R.id.widget_ring_5h_normal,
                R.id.widget_ring_5h_warning,
                R.id.widget_ring_5h_critical,
                R.id.widget_ring_5h_text,
            ),
            Ring(
                "7d",
                R.id.widget_ring_7d,
                R.id.widget_ring_7d_label,
                R.id.widget_ring_7d_normal,
                R.id.widget_ring_7d_warning,
                R.id.widget_ring_7d_critical,
                R.id.widget_ring_7d_text,
            ),
        )

        /**
         * Claude's 5-hour and weekly limits as rings in the header, coloured by
         * level (accent, warning from 80 %, urgent from 95 %). Hidden when the
         * app has no limits to show.
         */
        private fun bindRings(context: Context, views: RemoteViews, snapshot: AgentStatusSnapshot?, narrow: Boolean) {
            val now = System.currentTimeMillis()
            for (ring in rings) {
                val limit = snapshot?.limit(ring.label)
                val shown = limit != null && !(narrow && ring.label != "5h")
                val visibility = if (shown) View.VISIBLE else View.GONE
                views.setViewVisibility(ring.frame, visibility)
                views.setViewVisibility(ring.caption, visibility)
                if (!shown || limit == null) continue
                val percent = limit.percentAt(now)
                val level = limit.levelAt(now)
                for ((id, name) in listOf(ring.normal to "normal", ring.warning to "warning", ring.critical to "critical")) {
                    val active = name == level
                    views.setViewVisibility(id, if (active) View.VISIBLE else View.GONE)
                    if (active) views.setProgressBar(id, 100, percent, false)
                }
                views.setTextViewText(ring.text, percent.toString())
                val caption = context.getString(
                    if (ring.label == "5h") R.string.agent_widget_limit_5h else R.string.agent_widget_limit_7d,
                )
                views.setContentDescription(
                    ring.frame,
                    context.getString(R.string.agent_widget_limit_description, caption, percent),
                )
            }
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, AgentStatusWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val snapshot = AgentStatusStore.load(context)
            for (id in ids) {
                manager.updateAppWidget(id, build(context, snapshot, manager.getAppWidgetOptions(id)))
            }
        }

        private fun build(context: Context, snapshot: AgentStatusSnapshot?, options: Bundle?): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_agent_status)
            views.setOnClickPendingIntent(R.id.widget_root, openAgentsIntent(context))

            val minHeight = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0
            val compact = minHeight in 1 until COMPACT_MAX_HEIGHT_DP
            val minWidth = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) ?: 0
            bindRings(context, views, snapshot, narrow = minWidth in 1 until NARROW_MAX_WIDTH_DP)

            if (snapshot == null || !snapshot.monitoring) {
                views.setTextViewText(R.id.widget_count, "")
                views.setViewVisibility(R.id.widget_count, View.GONE)
                views.setTextViewText(R.id.widget_title, context.getString(R.string.agent_widget_title))
                views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                for (rowId in rowIds) views.setViewVisibility(rowId, View.GONE)
                views.setViewVisibility(R.id.widget_updated, View.GONE)
                return views
            }

            val count = snapshot.attentionCount
            views.setViewVisibility(R.id.widget_empty, View.GONE)
            views.setViewVisibility(R.id.widget_count, View.VISIBLE)
            views.setTextViewText(R.id.widget_count, count.toString())
            views.setTextViewText(
                R.id.widget_title,
                when {
                    count == 1 -> context.getString(R.string.agent_widget_one_needs_input)
                    count > 1 -> context.getString(R.string.agent_widget_needs_input)
                    else -> context.getString(R.string.agent_widget_all_clear)
                },
            )

            val rows = if (compact) 1 else rowIds.size
            rowIds.forEachIndexed { index, rowId ->
                val agent = snapshot.agents.getOrNull(index)
                if (index >= rows || agent == null) {
                    views.setViewVisibility(rowId, View.GONE)
                } else {
                    views.setViewVisibility(rowId, View.VISIBLE)
                    views.setTextViewText(rowId, "${agent.name} on ${agent.host} — ${agent.label.lowercase()}")
                    views.setTextColor(
                        rowId,
                        context.getColor(if (agent.urgent) R.color.agent_widget_urgent else R.color.agent_widget_on_surface),
                    )
                }
            }
            if (rows > 0 && snapshot.agents.isEmpty()) {
                views.setViewVisibility(R.id.widget_agent_1, View.VISIBLE)
                views.setTextViewText(R.id.widget_agent_1, context.getString(R.string.agent_widget_no_agents))
                views.setTextColor(R.id.widget_agent_1, context.getColor(R.color.agent_widget_on_surface_variant))
            }

            if (compact || snapshot.updatedAtMillis <= 0L) {
                views.setViewVisibility(R.id.widget_updated, View.GONE)
            } else {
                val time = DateFormat.getTimeFormat(context).format(Date(snapshot.updatedAtMillis))
                views.setViewVisibility(R.id.widget_updated, View.VISIBLE)
                views.setTextViewText(R.id.widget_updated, context.getString(R.string.agent_widget_updated, time))
            }
            return views
        }

        /** Launches (or brings back) the app with the "open agents" target. */
        fun openAgentsIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = AgentStatusStore.ACTION_OPEN_AGENTS
                putExtra(AgentStatusStore.EXTRA_LAUNCH_TARGET, AgentStatusStore.LAUNCH_TARGET_AGENTS)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(
                context,
                REQUEST_OPEN_AGENTS,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private const val REQUEST_OPEN_AGENTS = 3001
    }
}
