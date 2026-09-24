package com.gwitko.conduit

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
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
 *  - `start` {language?: String} -> null, begins a listening session.
 *  - `stop` -> null, ends audio capture and waits for the final result.
 *  - `cancel` -> null, drops the session without a result.
 *
 * Event channel (`conduit/speech_events`) emits maps:
 *  - {type: "status", value: "ready" | "listening" | "ended"}
 *  - {type: "partial", text}
 *  - {type: "result", text}
 *  - {type: "error", code: Int, message}
 *
 * Recognition prefers the on-device engine: the dedicated on-device
 * recognizer on Android 12+, otherwise EXTRA_PREFER_OFFLINE. No audio is
 * ever sent by this app to a third party; whether the system service stays
 * offline is the platform's decision. Everything runs on the main thread,
 * which is what SpeechRecognizer requires.
 */
class SpeechRecognitionBridge(private val activity: Activity) :
    EventChannel.StreamHandler {

    private var events: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var recognizerIsOnDevice = false
    private var pendingPermission: MethodChannel.Result? = null
    private var currentLanguage: String? = null
    private var retriedWithoutOnDevice = false

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(
                SpeechRecognizer.isRecognitionAvailable(activity),
            )
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> requestPermission(result)
            "start" -> {
                start(call.argument<String>("language"))
                result.success(null)
            }
            "stop" -> {
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

    private fun start(language: String?) {
        if (!hasPermission()) {
            emitError(SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS, "Microphone permission denied.")
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            emitError(ERROR_UNAVAILABLE, "No speech recognition service on this device.")
            return
        }
        cancel()
        currentLanguage = language?.takeIf { it.isNotBlank() }
        retriedWithoutOnDevice = false
        startRecognizer(preferOnDeviceRecognizer = true)
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
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, activity.packageName)
            currentLanguage?.let { putExtra(RecognizerIntent.EXTRA_LANGUAGE, it) }
        }
        created.startListening(intent)
    }

    private fun cancel() {
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
        }

        override fun onBeginningOfSpeech() {
            emit(mapOf("type" to "status", "value" to "listening"))
        }

        override fun onRmsChanged(rmsdB: Float) {}

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
            releaseRecognizer()
            emitError(error, describeError(error))
        }

        override fun onResults(results: Bundle?) {
            releaseRecognizer()
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
    }
}
