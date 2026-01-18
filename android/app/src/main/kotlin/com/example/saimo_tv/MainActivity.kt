package com.example.saimo_tv

import android.media.AudioManager
import android.media.audiofx.LoudnessEnhancer
import android.content.Context
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.saimo.tv/volume"
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var audioSessionId: Int = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Configura o áudio para streaming de mídia em TVs
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        
        // Garante que o volume de mídia está ativo
        volumeControlStream = AudioManager.STREAM_MUSIC
        
        // Define o modo de áudio para streaming (importante para Fire TV)
        try {
            audioManager.mode = AudioManager.MODE_NORMAL
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setVolumeBoost" -> {
                    val boostLevel = call.argument<Double>("boostLevel") ?: 1.0
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    val success = setVolumeBoost(boostLevel, sessionId)
                    result.success(success)
                }
                "getMaxVolume" -> {
                    val maxVolume = getMaxVolume()
                    result.success(maxVolume)
                }
                "getCurrentVolume" -> {
                    val currentVolume = getCurrentVolume()
                    result.success(currentVolume)
                }
                "setSystemVolume" -> {
                    val volumeLevel = call.argument<Int>("volumeLevel") ?: 0
                    setSystemVolume(volumeLevel)
                    result.success(true)
                }
                "enableLoudnessEnhancer" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    val gainMb = call.argument<Int>("gainMb") ?: 0
                    val success = enableLoudnessEnhancer(sessionId, gainMb)
                    result.success(success)
                }
                "disableLoudnessEnhancer" -> {
                    disableLoudnessEnhancer()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun setVolumeBoost(boostLevel: Double, sessionId: Int): Boolean {
        return try {
            // boostLevel vai de 1.0 a 2.0, onde:
            // 1.0 = 100% (normal)
            // 2.0 = 200% (boost máximo)
            
            if (boostLevel > 1.0) {
                // Calcula o ganho em millibels (mB)
                // O LoudnessEnhancer aceita ganho de -10000 a 10000 mB
                // 1000 mB = 10 dB de ganho
                val gainFactor = boostLevel - 1.0 // 0.0 a 1.0
                val gainMb = (gainFactor * 6000).toInt() // até 6000 mB (60 dB) de boost
                enableLoudnessEnhancer(sessionId, gainMb)
            } else {
                disableLoudnessEnhancer()
            }
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun enableLoudnessEnhancer(sessionId: Int, gainMb: Int): Boolean {
        return try {
            // Se o session id mudou, recria o enhancer
            if (audioSessionId != sessionId || loudnessEnhancer == null) {
                disableLoudnessEnhancer()
                audioSessionId = sessionId
                
                if (sessionId > 0) {
                    loudnessEnhancer = LoudnessEnhancer(sessionId)
                }
            }
            
            loudnessEnhancer?.let {
                it.setTargetGain(gainMb)
                it.enabled = true
            }
            
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun disableLoudnessEnhancer() {
        try {
            loudnessEnhancer?.enabled = false
            loudnessEnhancer?.release()
            loudnessEnhancer = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun getMaxVolume(): Int {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
    }

    private fun getCurrentVolume(): Int {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
    }

    private fun setSystemVolume(volumeLevel: Int) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val clampedVolume = volumeLevel.coerceIn(0, maxVolume)
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, clampedVolume, 0)
    }

    override fun onDestroy() {
        disableLoudnessEnhancer()
        super.onDestroy()
    }
}
