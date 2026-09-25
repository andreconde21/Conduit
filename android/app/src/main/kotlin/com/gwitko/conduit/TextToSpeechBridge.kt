package com.gwitko.conduit

import android.app.Activity
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Bridges Android's on-device [TextToSpeech] to Dart (Chat View "Read
 * replies aloud"). No audio or text leaves the phone through this app:
 * voices that need a network connection are never picked automatically and
 * are left out of the voice list.
 *
 * Method channel (`conduit/tts`):
 *  - `isAvailable` -> Boolean, whether a TTS engine initialised.
 *  - `voices` {language?: String} -> List<Map> of offline voices
 *    ({id, name, locale, quality}) for the language (all when null).
 *  - `speak` {text, id, language?, voice?} -> null. Flushes whatever was
 *    playing: the Dart side queues and sends one utterance at a time.
 *  - `stop` -> null, stops at once and releases audio focus.
 *  - `setRate` {rate: Double}, `setPitch` {pitch: Double} -> null.
 *  - `isInteractive` -> Boolean, whether the screen is on.
 *
 * Event channel (`conduit/tts_events`) emits maps:
 *  - {type: "start" | "done", id}
 *  - {type: "error", id, message}
 *  - {type: "stopped", id} when an utterance was interrupted.
 *
 * Audio focus: AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK with speech attributes,
 * so music ducks under the voice. Focus is held across consecutive
 * utterances and released a moment after the last one ends (no un-duck /
 * duck flicker between sentences). No foreground service: speech continues
 * with the screen off only while the Dart side keeps sending utterances.
 */
class TextToSpeechBridge(private val activity: Activity) :
    EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private val audioManager =
        activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var events: EventChannel.EventSink? = null
    private var tts: TextToSpeech? = null
    private var ready = false
    private var failed = false
    private val pending = mutableListOf<(Boolean) -> Unit>()
    private var rate = 1.0f
    private var pitch = 1.0f
    private var focusRequest: AudioFocusRequest? = null
    private var hasFocus = false
    private var speaking = false
    private val releaseFocus = Runnable { abandonFocus() }

    private val attributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANT)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> withEngine { ok -> result.success(ok) }
            "voices" -> withEngine { ok ->
                result.success(if (ok) voices(call.argument<String>("language")) else emptyList<Any>())
            }
            "speak" -> {
                val text = call.argument<String>("text") ?: ""
                val id = call.argument<String>("id") ?: ""
                val language = call.argument<String>("language")
                val voice = call.argument<String>("voice")
                withEngine { ok ->
                    if (ok) {
                        speak(text, id, language, voice)
                    } else {
                        emit(mapOf("type" to "error", "id" to id, "message" to "No text-to-speech engine."))
                    }
                }
                result.success(null)
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            "setRate" -> {
                rate = (call.argument<Double>("rate") ?: 1.0).toFloat().coerceIn(0.25f, 4f)
                result.success(null)
            }
            "setPitch" -> {
                pitch = (call.argument<Double>("pitch") ?: 1.0).toFloat().coerceIn(0.25f, 4f)
                result.success(null)
            }
            "isInteractive" -> {
                val power = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(power.isInteractive)
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

    fun dispose() {
        main.removeCallbacks(releaseFocus)
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: RuntimeException) {
        }
        tts = null
        ready = false
        abandonFocus()
        events = null
    }

    /** Runs [action] once the engine finished initialising (true) or failed. */
    private fun withEngine(action: (Boolean) -> Unit) {
        if (ready) return action(true)
        if (failed) return action(false)
        pending.add(action)
        if (tts != null) return
        tts = TextToSpeech(activity.applicationContext) { status ->
            main.post {
                ready = status == TextToSpeech.SUCCESS
                failed = !ready
                tts?.setOnUtteranceProgressListener(progress)
                tts?.setAudioAttributes(attributes)
                val waiting = pending.toList()
                pending.clear()
                waiting.forEach { it(ready) }
                if (failed) {
                    // Allow a later retry (an engine may be installed meanwhile).
                    tts?.shutdown()
                    tts = null
                    failed = false
                }
            }
        }
    }

    private fun speak(text: String, id: String, language: String?, voiceName: String?) {
        val engine = tts ?: return
        main.removeCallbacks(releaseFocus)
        requestFocus()
        applyVoice(engine, language, voiceName)
        engine.setSpeechRate(rate)
        engine.setPitch(pitch)
        val params = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1f)
        }
        speaking = true
        val status = engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, id)
        if (status != TextToSpeech.SUCCESS) {
            speaking = false
            emit(mapOf("type" to "error", "id" to id, "message" to "Could not speak."))
            scheduleFocusRelease()
        }
    }

    private fun stop() {
        speaking = false
        try {
            tts?.stop()
        } catch (_: RuntimeException) {
        }
        main.removeCallbacks(releaseFocus)
        abandonFocus()
    }

    private fun applyVoice(engine: TextToSpeech, language: String?, voiceName: String?) {
        val all = try {
            engine.voices ?: emptySet()
        } catch (_: RuntimeException) {
            emptySet<Voice>()
        }
        if (!voiceName.isNullOrBlank()) {
            val chosen = all.firstOrNull { it.name == voiceName }
            if (chosen != null && engine.voice?.name != chosen.name) {
                engine.voice = chosen
            }
            if (chosen != null) return
        }
        val locale = if (language.isNullOrBlank()) {
            Locale.getDefault()
        } else {
            Locale.forLanguageTag(language)
        }
        val best = offline(all)
            .filter { matches(it.locale, locale) }
            .sortedWith(
                compareByDescending<Voice> { it.locale.country == locale.country }
                    .thenByDescending { it.quality },
            )
            .firstOrNull()
        if (best != null) {
            if (engine.voice?.name != best.name) engine.voice = best
        } else {
            engine.language = locale
        }
    }

    private fun voices(language: String?): List<Map<String, Any>> {
        val all = try {
            tts?.voices ?: emptySet()
        } catch (_: RuntimeException) {
            emptySet<Voice>()
        }
        val locale = language?.takeIf { it.isNotBlank() }?.let { Locale.forLanguageTag(it) }
        return offline(all)
            .filter { locale == null || matches(it.locale, locale) }
            .sortedWith(compareBy<Voice> { it.locale.toLanguageTag() }.thenByDescending { it.quality }.thenBy { it.name })
            .map {
                mapOf(
                    "id" to it.name,
                    "name" to it.name,
                    "locale" to it.locale.toLanguageTag(),
                    "quality" to it.quality,
                )
            }
    }

    private fun offline(voices: Collection<Voice>): List<Voice> = voices.filter {
        !it.isNetworkConnectionRequired &&
            !it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
    }

    private fun matches(voice: Locale, wanted: Locale): Boolean =
        voice.language == wanted.language

    private val progress = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {
            main.post { emit(mapOf("type" to "start", "id" to (utteranceId ?: ""))) }
        }

        override fun onDone(utteranceId: String?) {
            main.post {
                speaking = false
                scheduleFocusRelease()
                emit(mapOf("type" to "done", "id" to (utteranceId ?: "")))
            }
        }

        override fun onStop(utteranceId: String?, interrupted: Boolean) {
            main.post {
                emit(mapOf("type" to "stopped", "id" to (utteranceId ?: "")))
            }
        }

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String?) {
            onError(utteranceId, TextToSpeech.ERROR)
        }

        override fun onError(utteranceId: String?, errorCode: Int) {
            main.post {
                speaking = false
                scheduleFocusRelease()
                emit(
                    mapOf(
                        "type" to "error",
                        "id" to (utteranceId ?: ""),
                        "message" to "Text-to-speech failed ($errorCode).",
                    ),
                )
            }
        }
    }

    private fun scheduleFocusRelease() {
        main.removeCallbacks(releaseFocus)
        main.postDelayed(releaseFocus, FOCUS_RELEASE_DELAY_MS)
    }

    private fun requestFocus() {
        if (hasFocus) return
        hasFocus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener { change ->
                    if (change == AudioManager.AUDIOFOCUS_LOSS) main.post { stopForFocusLoss() }
                }
                .build()
            focusRequest = request
            audioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                null,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
            ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    /** A call or another app took the audio for good: go quiet. */
    private fun stopForFocusLoss() {
        if (!speaking) return
        stop()
        emit(mapOf("type" to "interrupted"))
    }

    private fun abandonFocus() {
        if (!hasFocus) return
        hasFocus = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
        }
        focusRequest = null
    }

    private fun emit(event: Map<String, Any?>) {
        events?.success(event)
    }

    companion object {
        const val METHOD_CHANNEL = "conduit/tts"
        const val EVENT_CHANNEL = "conduit/tts_events"
        private const val FOCUS_RELEASE_DELAY_MS = 700L
    }
}
