package com.gwitko.conduit

import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import java.lang.ref.WeakReference

/**
 * Quick-settings tile: active while at least one agent needs input, with
 * the attention count in the subtitle. Tapping opens the app on the agent
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
        tile.label = getString(R.string.agent_tile_label)
        tile.icon = Icon.createWithResource(this, R.drawable.ic_agent_tile)
        tile.state = if (live && count > 0) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        val subtitle = when {
            !live -> getString(R.string.agent_tile_not_monitoring)
            count == 0 -> getString(R.string.agent_widget_all_clear)
            count == 1 -> getString(R.string.agent_tile_one_needs_input)
            else -> getString(R.string.agent_tile_needs_input, count)
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
