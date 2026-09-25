package com.gwitko.conduit

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * One agent line as rendered by the widget and tile. Mirrors
 * `AgentStatusEntry` on the Dart side.
 */
data class AgentStatusLine(val name: String, val host: String, val state: String, val label: String) {
    /** Needs input or blocked: the states a human should act on. */
    val urgent: Boolean get() = state == "needsInput" || state == "blocked"
}

/**
 * One account limit window (Claude's `5h` or `7d`) as a ring. Mirrors
 * `AgentStatusLimit` on the Dart side; `level` is normal, warning (80 %+)
 * or critical (95 %+).
 */
data class AgentStatusLimitRing(val label: String, val usedPct: Int, val level: String, val resetsAtMillis: Long) {
    /** What to draw at [nowMillis]: 0 once the window has reset. */
    fun percentAt(nowMillis: Long): Int =
        if (resetsAtMillis in 1..nowMillis) 0 else usedPct.coerceIn(0, 100)

    fun levelAt(nowMillis: Long): String = if (percentAt(nowMillis) == 0) "normal" else level

    fun toJson(): JSONObject = JSONObject()
        .put("label", label)
        .put("usedPct", usedPct)
        .put("level", level)
        .apply { if (resetsAtMillis > 0) put("resetsAt", resetsAtMillis) }
}

/** Mirrors `AgentStatusSnapshot` on the Dart side. */
data class AgentStatusSnapshot(
    val monitoring: Boolean,
    val attentionCount: Int,
    val agents: List<AgentStatusLine>,
    val updatedAtMillis: Long,
    val limits: List<AgentStatusLimitRing> = emptyList(),
) {
    fun limit(label: String): AgentStatusLimitRing? = limits.firstOrNull { it.label == label }

    companion object {
        fun parse(json: String): AgentStatusSnapshot? = try {
            val root = JSONObject(json)
            val agents = root.optJSONArray("agents") ?: JSONArray()
            val limits = root.optJSONArray("limits") ?: JSONArray()
            AgentStatusSnapshot(
                monitoring = root.optBoolean("monitoring", false),
                attentionCount = root.optInt("attentionCount", 0),
                agents = (0 until agents.length()).map { index ->
                    val agent = agents.getJSONObject(index)
                    AgentStatusLine(
                        name = agent.optString("name"),
                        host = agent.optString("host"),
                        state = agent.optString("state"),
                        label = agent.optString("label"),
                    )
                },
                updatedAtMillis = root.optLong("updatedAt", 0L),
                limits = (0 until limits.length()).map { index ->
                    val limit = limits.getJSONObject(index)
                    AgentStatusLimitRing(
                        label = limit.optString("label"),
                        usedPct = limit.optInt("usedPct", 0),
                        level = limit.optString("level", "normal"),
                        resetsAtMillis = limit.optLong("resetsAt", 0L),
                    )
                },
            )
        } catch (_: Exception) {
            null
        }
    }
}

/**
 * Persists the last snapshot Dart pushed so the widget and tile can render
 * without the Flutter engine running, and the launch target the widget or
 * tile asked for until Dart consumes it.
 */
object AgentStatusStore {
    private const val PREFS = "agent_status_widget"
    private const val KEY_SNAPSHOT = "snapshot"
    private const val KEY_LAUNCH_TARGET = "launch_target"

    /** Intent extra carrying the launch target ("agents"). */
    const val EXTRA_LAUNCH_TARGET = "com.gwitko.conduit.LAUNCH_TARGET"
    const val LAUNCH_TARGET_AGENTS = "agents"

    /** Distinct action so the widget/tile PendingIntents never collide with the notification ones. */
    const val ACTION_OPEN_AGENTS = "com.gwitko.conduit.action.OPEN_AGENTS"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun save(context: Context, json: String) {
        prefs(context).edit().putString(KEY_SNAPSHOT, json).apply()
    }

    fun load(context: Context): AgentStatusSnapshot? =
        prefs(context).getString(KEY_SNAPSHOT, null)?.let(AgentStatusSnapshot::parse)

    /**
     * Marks the snapshot as no longer live (the engine went away). The limit
     * rings stay: they are per account and fall to 0 when their window
     * resets.
     */
    fun markNotMonitoring(context: Context) {
        val current = load(context) ?: return
        if (!current.monitoring) return
        val json = JSONObject()
            .put("version", 2)
            .put("monitoring", false)
            .put("attentionCount", 0)
            .put("updatedAt", current.updatedAtMillis)
            .put("agents", JSONArray())
            .put("limits", JSONArray(current.limits.map { it.toJson() }))
        save(context, json.toString())
    }

    fun setLaunchTarget(context: Context, target: String?) {
        prefs(context).edit().apply {
            if (target == null) remove(KEY_LAUNCH_TARGET) else putString(KEY_LAUNCH_TARGET, target)
        }.apply()
    }

    fun consumeLaunchTarget(context: Context): String? {
        val target = prefs(context).getString(KEY_LAUNCH_TARGET, null)
        if (target != null) setLaunchTarget(context, null)
        return target
    }

    /** Refreshes every home-screen widget and the quick-settings tile. */
    fun refreshSurfaces(context: Context) {
        AgentStatusWidgetProvider.updateAll(context)
        AgentStatusTileService.refresh()
    }
}
