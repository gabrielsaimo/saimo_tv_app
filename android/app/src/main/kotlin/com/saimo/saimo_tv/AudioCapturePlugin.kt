package com.saimo.saimo_tv

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

/**
 * Plugin para capturar áudio do dispositivo para CC (Closed Captioning).
 * 
 * Usa AudioRecord com VOICE_RECOGNITION para capturar áudio ambiente
 * que inclui o áudio do TV quando não há fones de ouvido conectados.
 */
class AudioCapturePlugin(private val flutterEngine: FlutterEngine) {
    
    companion object {
        private const val TAG = "AudioCapturePlugin"
        private const val METHOD_CHANNEL = "com.saimo.saimo_tv/audio_capture"
        private const val EVENT_CHANNEL = "com.saimo.saimo_tv/caption_audio"
        
        // Audio config - 16kHz mono para speech recognition
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    }
    
    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private var recordingThread: Thread? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    
    // Buffer size for smooth audio streaming
    private val bufferSize = maxOf(
        AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT) * 2,
        4096
    )
    
    init {
        setupChannels()
    }
    
    private fun setupChannels() {
        // Method channel for control
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCapture" -> {
                        val success = startCapture()
                        result.success(success)
                    }
                    "stopCapture" -> {
                        stopCapture()
                        result.success(true)
                    }
                    "isCapturing" -> {
                        result.success(isRecording)
                    }
                    else -> result.notImplemented()
                }
            }
        
        // Event channel for audio data streaming
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    Log.d(TAG, "Audio EventChannel connected")
                }
                
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    Log.d(TAG, "Audio EventChannel disconnected")
                }
            })
    }
    
    private fun startCapture(): Boolean {
        if (isRecording) {
            Log.w(TAG, "Already recording")
            return true
        }
        
        try {
            // Try different audio sources
            val audioSources = listOf(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,  // Best for TV audio
                MediaRecorder.AudioSource.MIC,
                MediaRecorder.AudioSource.DEFAULT
            )
            
            var recordCreated = false
            for (source in audioSources) {
                try {
                    audioRecord = AudioRecord(
                        source,
                        SAMPLE_RATE,
                        CHANNEL_CONFIG,
                        AUDIO_FORMAT,
                        bufferSize
                    )
                    
                    if (audioRecord?.state == AudioRecord.STATE_INITIALIZED) {
                        Log.d(TAG, "AudioRecord created with source: $source")
                        recordCreated = true
                        break
                    } else {
                        audioRecord?.release()
                        audioRecord = null
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed with source $source: ${e.message}")
                }
            }
            
            if (!recordCreated) {
                Log.e(TAG, "Failed to create AudioRecord with any source")
                return false
            }
            
            audioRecord?.startRecording()
            isRecording = true
            
            // Start recording thread
            recordingThread = thread(name = "AudioCapture") {
                captureLoop()
            }
            
            Log.d(TAG, "Audio capture started - buffer size: $bufferSize bytes")
            return true
            
        } catch (e: SecurityException) {
            Log.e(TAG, "Permission denied: ${e.message}")
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start recording: ${e.message}")
            return false
        }
    }
    
    private fun captureLoop() {
        val buffer = ByteArray(bufferSize)
        
        while (isRecording && audioRecord != null) {
            try {
                val bytesRead = audioRecord?.read(buffer, 0, bufferSize) ?: -1
                
                if (bytesRead > 0) {
                    // Send to Flutter on main thread
                    val audioData = buffer.copyOf(bytesRead)
                    mainHandler.post {
                        eventSink?.success(audioData)
                    }
                } else if (bytesRead == AudioRecord.ERROR_INVALID_OPERATION) {
                    Log.e(TAG, "AudioRecord error: invalid operation")
                    break
                } else if (bytesRead == AudioRecord.ERROR_BAD_VALUE) {
                    Log.e(TAG, "AudioRecord error: bad value")
                    break
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error reading audio: ${e.message}")
                break
            }
        }
        
        Log.d(TAG, "Capture loop ended")
    }
    
    private fun stopCapture() {
        isRecording = false
        
        try {
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping recording: ${e.message}")
        }
        
        recordingThread?.join(1000)
        recordingThread = null
        
        Log.d(TAG, "Audio capture stopped")
    }
    
    fun dispose() {
        stopCapture()
    }
}
