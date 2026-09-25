package com.gwitko.conduit

import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import java.lang.ref.WeakReference

/**
 * Quick-settings tile: active while at least one agent needs input, with
 * the attention count in the subtitle, else Claude's 5-hour and weekly
 * limits ("5h 42% · wk 18%", and as rings in the icon). Tapping opens the app on the agent
 * attention sheet.
 *
 * The tile reads the stored snapshot whenever it becomes visible; while it
 * is visible, a push from Dart refreshes it through [refresh].
 */
class AgentStatusTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        listening = WeakReference(this)
        render()
    }

    override fun onStopListening() {
        listening = null
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(AgentStatusWidgetProvider.openAgentsIntent(this))
        } else {
            val intent = Intent(this, MainActivity::class.java).apply {
                action = AgentStatusStore.ACTION_OPEN_AGENTS
                putExtra(AgentStatusStore.EXTRA_LAUNCH_TARGET, AgentStatusStore.LAUNCH_TARGET_AGENTS)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun render() {
        val tile = qsTile ?: return
        val snapshot = AgentStatusStore.load(this)
        val live = snapshot != null && snapshot.monitoring
        val count = snapshot?.attentionCount ?: 0
        val now = System.currentTimeMillis()
        val fiveHour = snapshot?.limit("5h")
        val week = snapshot?.limit("7d")
        tile.label = getString(R.string.agent_tile_label)
        // With Claude's limits known, the icon is their rings (outer: 5 h,
        // inner: week); the system tints it like any tile icon.
        tile.icon = if (fiveHour != null || week != null) {
            LimitRingsIcon.create(fiveHour?.percentAt(now), week?.percentAt(now))
        } else {
            Icon.createWithResource(this, R.drawable.ic_agent_tile)
        }
        tile.state = if (live && count > 0) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        val limits = if (fiveHour != null || week != null) {
            getString(
                R.string.agent_tile_limits,
                fiveHour?.let { "${it.percentAt(now)}%" } ?: "–",
                week?.let { "${it.percentAt(now)}%" } ?: "–",
            )
        } else {
            null
        }
        // Agents needing input come first; otherwise the limits.
        val subtitle = when {
            live && count == 1 -> getString(R.string.agent_tile_one_needs_input)
            live && count > 1 -> getString(R.string.agent_tile_needs_input, count)
            limits != null -> limits
            !live -> getString(R.string.agent_tile_not_monitoring)
            else -> getString(R.string.agent_widget_all_clear)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = subtitle
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            tile.stateDescription = subtitle
        }
        tile.contentDescription = "${tile.label}: $subtitle"
        tile.updateTile()
    }

    companion object {
        private var listening: WeakReference<AgentStatusTileService>? = null

        /** Re-renders the tile if it is currently visible. */
        fun refresh() {
            listening?.get()?.render()
        }
    }
}
