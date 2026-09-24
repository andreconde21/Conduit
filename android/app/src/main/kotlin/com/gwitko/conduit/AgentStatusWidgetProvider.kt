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
