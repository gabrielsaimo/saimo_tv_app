package com.saimo.saimo_tv

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.StorageService
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

/**
 * Plugin nativo para reconhecimento de fala usando Vosk.
 * 
 * Este plugin processa áudio PCM enviado do Flutter e retorna
 * resultados de transcrição em tempo real.
 */
class VoskCaptionPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var context: Context? = null
    
    private var model: Model? = null
    private var recognizer: Recognizer? = null
    private var isModelLoaded = false
    private var isRecognizing = false
    
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    
    companion object {
        private const val SAMPLE_RATE = 16000.0f
        private const val MODEL_NAME = "vosk-model-small-pt-0.3"
    }
    
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        
        methodChannel = MethodChannel(binding.binaryMessenger, "com.saimo.saimo_tv/vosk_caption")
        methodChannel.setMethodCallHandler(this)
        
        eventChannel = EventChannel(binding.binaryMessenger, "com.saimo.saimo_tv/vosk_results")
        eventChannel.setStreamHandler(this)
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cleanup()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        context = null
    }
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initModel" -> {
                executor.execute {
                    try {
                        initializeModel()
                        mainHandler.post { result.success(true) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("INIT_ERROR", e.message, null) }
                    }
                }
            }
            "isModelLoaded" -> {
                result.success(isModelLoaded)
            }
            "startRecognition" -> {
                try {
                    startRecognition()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("START_ERROR", e.message, null)
                }
            }
            "stopRecognition" -> {
                stopRecognition()
                result.success(true)
            }
            "processAudio" -> {
                val audioData = call.argument<ByteArray>("audio")
                if (audioData != null) {
                    executor.execute {
                        processAudioData(audioData)
                    }
                    result.success(true)
                } else {
                    result.error("NO_DATA", "No audio data provided", null)
                }
            }
            "cleanup" -> {
                cleanup()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }
    
    private fun initializeModel() {
        if (isModelLoaded && model != null) {
            sendEvent("status", "Model already loaded")
            return
        }
        
        val ctx = context ?: throw IOException("Context not available")
        
        sendEvent("status", "Unpacking model...")
        
        // Try to load model from assets
        StorageService.unpack(ctx, MODEL_NAME, "model",
            { loadedModel ->
                model = loadedModel
                isModelLoaded = true
                sendEvent("status", "Model loaded")
                sendEvent("modelLoaded", "true")
            },
            { exception ->
                sendEvent("error", "Failed to load model: ${exception.message}")
            }
        )
    }
    
    private fun startRecognition() {
        if (!isModelLoaded || model == null) {
            throw IllegalStateException("Model not loaded")
        }
        
        if (isRecognizing) {
            return
        }
        
        recognizer = Recognizer(model, SAMPLE_RATE)
        isRecognizing = true
        sendEvent("status", "Recognition started")
    }
    
    private fun stopRecognition() {
        isRecognizing = false
        
        // Get final result
        recognizer?.let { rec ->
            val finalResult = rec.finalResult
            if (finalResult.isNotEmpty()) {
                parseFinalResult(finalResult)
            }
            rec.close()
        }
        recognizer = null
        
        sendEvent("status", "Recognition stopped")
    }
    
    private fun processAudioData(audioBytes: ByteArray) {
        if (!isRecognizing || recognizer == null) {
            return
        }
        
        try {
            // Convert bytes to shorts (16-bit PCM)
            val shortBuffer = ShortArray(audioBytes.size / 2)
            ByteBuffer.wrap(audioBytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(shortBuffer)
            
            // Feed to recognizer
            val hasResult = recognizer!!.acceptWaveForm(shortBuffer, shortBuffer.size)
            
            if (hasResult) {
                // Final result for this phrase
                val result = recognizer!!.result
                parseFinalResult(result)
            } else {
                // Partial result
                val partial = recognizer!!.partialResult
                parsePartialResult(partial)
            }
        } catch (e: Exception) {
            sendEvent("error", "Processing error: ${e.message}")
        }
    }
    
    private fun parseFinalResult(jsonStr: String) {
        try {
            val json = JSONObject(jsonStr)
            val text = json.optString("text", "")
            if (text.isNotEmpty()) {
                sendEvent("final", text)
            }
        } catch (e: Exception) {
            // Ignore parse errors
        }
    }
    
    private fun parsePartialResult(jsonStr: String) {
        try {
            val json = JSONObject(jsonStr)
            val text = json.optString("partial", "")
            if (text.isNotEmpty()) {
                sendEvent("partial", text)
            }
        } catch (e: Exception) {
            // Ignore parse errors
        }
    }
    
    private fun sendEvent(type: String, data: String) {
        mainHandler.post {
            eventSink?.success(mapOf("type" to type, "data" to data))
        }
    }
    
    private fun cleanup() {
        isRecognizing = false
        recognizer?.close()
        recognizer = null
        model?.close()
        model = null
        isModelLoaded = false
    }
    
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }
    
    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
