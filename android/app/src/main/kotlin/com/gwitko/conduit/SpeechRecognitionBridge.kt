package com.gwitko.conduit

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Android's on-device [SpeechRecognizer] to Dart.
 *
 * Method channel (`conduit/speech`):
 *  - `isAvailable` -> Boolean, whether any recognition service exists.
 *  - `hasPermission` -> Boolean, RECORD_AUDIO state.
 *  - `requestPermission` -> Boolean, resolves once the system dialog closes.
 *  - `openSettings` -> Boolean, opens the system voice input settings (or
 *    Settings itself when a vendor build lacks that screen); false when
 *    neither could be opened.
 *  - `start` {language?: String, continuous?, restart?, muteBeeps?,
 *    completeSilenceMillis?, possiblyCompleteSilenceMillis?,
 *    minimumLengthMillis?} -> null, begins a listening session.
 *  - `stop` -> null, ends audio capture and waits for the final result.
 *  - `cancel` -> null, drops the session without a result.
 *
 * Event channel (`conduit/speech_events`) emits maps:
 *  - {type: "status", value: "ready" | "listening" | "ended"}
 *  - {type: "level", value: 0..1} a few times a second (input loudness)
 *  - {type: "partial", text}
 *  - {type: "result", text}
 *  - {type: "error", code: Int, message}
 *
 * Recognition prefers the on-device engine: the dedicated on-device
 * recognizer on Android 12+, otherwise EXTRA_PREFER_OFFLINE. No audio is
 * ever sent by this app to a third party; whether the system service stays
 * offline is the platform's decision. Everything runs on the main thread,
 * which is what SpeechRecognizer requires.
 *
 * Continuous dictation: Android's recognizer (Google's on-device one
 * included) ends every session after a short pause and mostly ignores the
 * EXTRA_SPEECH_INPUT_* silence extras, so the Dart side restarts it after
 * each phrase (`start` with restart=true). In a continuous session the
 * recognizer object is kept between phrases (a restart only calls
 * startListening again) and released by `cancel`.
 *
 * Restart beeps: there is no public extra to silence the recognizer's
 * start/stop earcons. With muteBeeps, once the first phrase is listening
 * (so the user heard the first "ready" beep) the music, notification and
 * system streams are muted for the rest of the continuous session, and
 * restored on `stop` (before the final stop beep), `cancel`, when the
 * activity stops, and on dispose. Streams the user had already muted are
 * left alone. Muting can fail under Do Not Disturb; the beeps then stay.
 * This is opt-in (off by default in Settings → Speech): a crash or a kill
 * while muted would leave the phone muted, so the muted streams and their
 * pre-mute levels are written to SharedPreferences before muting and
 * restored (then cleared) when the bridge is created on the next start.
 */
class SpeechRecognitionBridge(private val activity: Activity) :
    EventChannel.StreamHandler {

    private var events: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var recognizerIsOnDevice = false
    private var pendingPermission: MethodChannel.Result? = null
    private var currentLanguage: String? = null
    private var retriedWithoutOnDevice = false
    private var options = ListenOptions()
    private val main = Handler(Looper.getMainLooper())
    private val audioManager =
        activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val mutedStreams = mutableListOf<Int>()
    private var lastLevelAt = 0L
    private val muteAfterFirstBeep = Runnable { muteEarcons() }
    private val prefs =
        activity.getSharedPreferences(MUTE_PREFS, Context.MODE_PRIVATE)

    init {
        // A previous run died while muted: give the user their sound back.
        restorePersistedMute()
    }

    /** Per-start tuning sent by the Dart side (see the class docs). */
    private data class ListenOptions(
        val continuous: Boolean = false,
        val restart: Boolean = false,
        val muteBeeps: Boolean = false,
        val completeSilenceMillis: Long? = null,
        val possiblyCompleteSilenceMillis: Long? = null,
        val minimumLengthMillis: Long? = null,
    )

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(
                SpeechRecognizer.isRecognitionAvailable(activity),
            )
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> requestPermission(result)
            "openSettings" -> result.success(openSettings())
            "start" -> {
                start(
                    call.argument<String>("language"),
                    ListenOptions(
                        continuous = call.argument<Boolean>("continuous") ?: false,
                        restart = call.argument<Boolean>("restart") ?: false,
                        muteBeeps = call.argument<Boolean>("muteBeeps") ?: false,
                        completeSilenceMillis =
                            call.argument<Number>("completeSilenceMillis")?.toLong(),
                        possiblyCompleteSilenceMillis =
                            call.argument<Number>("possiblyCompleteSilenceMillis")?.toLong(),
                        minimumLengthMillis =
                            call.argument<Number>("minimumLengthMillis")?.toLong(),
                    ),
                )
                result.success(null)
            }
            "stop" -> {
                // Let the final stop beep play.
                restoreVolume()
                recognizer?.stopListening()
                result.success(null)
            }
            "cancel" -> {
                cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
        return true
    }

    fun dispose() {
        cancel()
        events = null
    }

    /** The app left the foreground: never leave the user's streams muted. */
    fun onStop() {
        restoreVolume()
    }

    /**
     * Voice input settings pick the recognizer ("Voice input" / "Default
     * voice input app"); not every vendor build has the screen, so fall
     * back to Settings itself.
     */
    private fun openSettings(): Boolean {
        for (action in listOf(
            Settings.ACTION_VOICE_INPUT_SETTINGS,
            Settings.ACTION_SETTINGS,
        )) {
            try {
                activity.startActivity(Intent(action))
                return true
            } catch (_: ActivityNotFoundException) {
                // Try the next screen.
            } catch (_: SecurityException) {
                // Try the next screen.
            }
        }
        return false
    }

    private fun hasPermission(): Boolean {
        return activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("busy", "A permission request is already showing.", null)
            return
        }
        pendingPermission = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.RECORD_AUDIO),
            PERMISSION_REQUEST_CODE,
        )
    }

    private fun start(language: String?, listen: ListenOptions) {
        if (!hasPermission()) {
            emitError(SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS, "Microphone permission denied.")
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            emitError(ERROR_UNAVAILABLE, "No speech recognition service on this device.")
            return
        }
        val existing = recognizer
        currentLanguage = language?.takeIf { it.isNotBlank() }
        options = listen
        if (listen.restart && listen.continuous && existing != null) {
            // Next phrase of a continuous session: reuse the recognizer.
            try {
                existing.startListening(buildIntent())
                return
            } catch (_: RuntimeException) {
                // Fall through to a fresh recognizer.
            }
        }
        cancel()
        options = listen
        retriedWithoutOnDevice = false
        startRecognizer(preferOnDeviceRecognizer = true)
    }

    private fun buildIntent(): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, activity.packageName)
            currentLanguage?.let { putExtra(RecognizerIntent.EXTRA_LANGUAGE, it) }
            // Often ignored (Google's on-device recognizer among them); the
            // Dart side restarts after each phrase regardless.
            options.completeSilenceMillis?.let {
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, it)
            }
            options.possiblyCompleteSilenceMillis?.let {
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                    it,
                )
            }
            options.minimumLengthMillis?.let {
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, it)
            }
        }

    private fun startRecognizer(preferOnDeviceRecognizer: Boolean) {
        val useOnDevice = preferOnDeviceRecognizer &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)
        val created = try {
            if (useOnDevice) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
            } else {
                SpeechRecognizer.createSpeechRecognizer(activity)
            }
        } catch (error: RuntimeException) {
            emitError(ERROR_UNAVAILABLE, error.message ?: "Could not create the recognizer.")
            return
        }
        recognizer = created
        recognizerIsOnDevice = useOnDevice
        created.setRecognitionListener(listener)
        created.startListening(buildIntent())
    }

    private fun cancel() {
        restoreVolume()
        val current = recognizer ?: return
        recognizer = null
        try {
            current.cancel()
            current.destroy()
        } catch (_: RuntimeException) {
            // The service may already be gone; there is nothing left to free.
        }
    }

    private fun releaseRecognizer() {
        val current = recognizer ?: return
        recognizer = null
        try {
            current.destroy()
        } catch (_: RuntimeException) {
        }
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            emit(mapOf("type" to "status", "value" to "ready"))
            if (options.continuous && options.muteBeeps && mutedStreams.isEmpty()) {
                // After the first "ready" beep has played.
                main.removeCallbacks(muteAfterFirstBeep)
                main.postDelayed(muteAfterFirstBeep, BEEP_GRACE_MS)
            }
        }

        override fun onBeginningOfSpeech() {
            emit(mapOf("type" to "status", "value" to "listening"))
        }

        override fun onRmsChanged(rmsdB: Float) {
            val now = SystemClock.elapsedRealtime()
            if (now - lastLevelAt < LEVEL_INTERVAL_MS) return
            lastLevelAt = now
            // rmsdB runs from about -2 (silence) to 10 (loud speech).
            val level = ((rmsdB + 2f) / 12f).coerceIn(0f, 1f)
            emit(mapOf("type" to "level", "value" to level.toDouble()))
        }

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() {
            emit(mapOf("type" to "status", "value" to "ended"))
        }

        override fun onError(error: Int) {
            // The on-device engine may lack the requested language (or any
            // language pack at all): retry once with the default service,
            // which can still honour EXTRA_PREFER_OFFLINE.
            val languageProblem = error == ERROR_LANGUAGE_NOT_SUPPORTED ||
                error == ERROR_LANGUAGE_UNAVAILABLE ||
                error == SpeechRecognizer.ERROR_SERVER
            if (recognizerIsOnDevice && languageProblem && !retriedWithoutOnDevice) {
                retriedWithoutOnDevice = true
                cancel()
                startRecognizer(preferOnDeviceRecognizer = false)
                return
            }
            // A continuous session keeps the recognizer for the next phrase.
            if (!options.continuous) releaseRecognizer()
            emitError(error, describeError(error))
        }

        override fun onResults(results: Bundle?) {
            if (!options.continuous) releaseRecognizer()
            val text = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?: ""
            emit(mapOf("type" to "result", "text" to text))
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val text = partialResults
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?: return
            emit(mapOf("type" to "partial", "text" to text))
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun muteEarcons() {
        if (recognizer == null || !options.continuous) return
        val toMute = EARCON_STREAMS.filter { stream ->
            !mutedStreams.contains(stream) &&
                !audioManager.isStreamMute(stream)
        }
        if (toMute.isEmpty()) return
        // Written (synchronously) before anything is muted, so a crash in
        // between can still be undone on the next start.
        val record = (mutedStreams + toMute).joinToString(",") { stream ->
            "$stream:${audioManager.getStreamVolume(stream)}"
        }
        prefs.edit().putString(MUTED_KEY, record).commit()
        for (stream in toMute) {
            try {
                audioManager.adjustStreamVolume(stream, AudioManager.ADJUST_MUTE, 0)
                mutedStreams.add(stream)
            } catch (_: SecurityException) {
                // Do Not Disturb: the stream cannot be changed; beeps stay.
            }
        }
    }

    private fun restorePersistedMute() {
        val record = prefs.getString(MUTED_KEY, null) ?: return
        for (entry in record.split(',')) {
            val parts = entry.split(':')
            val stream = parts.getOrNull(0)?.toIntOrNull() ?: continue
            val level = parts.getOrNull(1)?.toIntOrNull() ?: 0
            try {
                audioManager.adjustStreamVolume(stream, AudioManager.ADJUST_UNMUTE, 0)
                if (level > 0 && audioManager.getStreamVolume(stream) == 0) {
                    audioManager.setStreamVolume(stream, level, 0)
                }
            } catch (_: SecurityException) {
            }
        }
        prefs.edit().remove(MUTED_KEY).apply()
    }

    private fun restoreVolume() {
        main.removeCallbacks(muteAfterFirstBeep)
        for (stream in mutedStreams) {
            try {
                audioManager.adjustStreamVolume(stream, AudioManager.ADJUST_UNMUTE, 0)
            } catch (_: SecurityException) {
            }
        }
        if (mutedStreams.isNotEmpty()) {
            mutedStreams.clear()
            prefs.edit().remove(MUTED_KEY).apply()
        }
    }

    private fun emit(event: Map<String, Any?>) {
        events?.success(event)
    }

    private fun emitError(code: Int, message: String) {
        emit(mapOf("type" to "error", "code" to code, "message" to message))
    }

    private fun describeError(code: Int): String = when (code) {
        SpeechRecognizer.ERROR_AUDIO -> "Audio recording failed."
        SpeechRecognizer.ERROR_CLIENT -> "Speech recognition was interrupted."
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission denied."
        SpeechRecognizer.ERROR_NETWORK,
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Speech recognition needs a network connection."
        SpeechRecognizer.ERROR_NO_MATCH -> "Nothing was recognized."
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Speech recognition is busy."
        SpeechRecognizer.ERROR_SERVER -> "The speech service failed."
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech was heard."
        ERROR_LANGUAGE_NOT_SUPPORTED,
        ERROR_LANGUAGE_UNAVAILABLE -> "This language is not available for offline recognition."
        ERROR_UNAVAILABLE -> "No speech recognition service on this device."
        else -> "Speech recognition failed ($code)."
    }

    companion object {
        const val METHOD_CHANNEL = "conduit/speech"
        const val EVENT_CHANNEL = "conduit/speech_events"
        const val PERMISSION_REQUEST_CODE = 2003

        // SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED / _UNAVAILABLE are
        // API 31 constants; spelled out so the file compiles for lower SDKs.
        private const val ERROR_LANGUAGE_NOT_SUPPORTED = 12
        private const val ERROR_LANGUAGE_UNAVAILABLE = 13
        private const val ERROR_UNAVAILABLE = 1000
        private const val LEVEL_INTERVAL_MS = 100L
        private const val BEEP_GRACE_MS = 600L
        private const val MUTE_PREFS = "conduit_speech"
        private const val MUTED_KEY = "muted_streams"
        private val EARCON_STREAMS = listOf(
            AudioManager.STREAM_MUSIC,
            AudioManager.STREAM_NOTIFICATION,
            AudioManager.STREAM_SYSTEM,
        )
    }
}
