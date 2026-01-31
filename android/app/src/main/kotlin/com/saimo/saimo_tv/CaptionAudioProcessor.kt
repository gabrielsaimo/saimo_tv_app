package com.saimo.saimo_tv

import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.AudioProcessor.AudioFormat
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * AudioProcessor that captures audio samples from ExoPlayer/Media3
 * and forwards them to a callback for speech recognition.
 * 
 * This processor sits in the ExoPlayer audio pipeline and captures
 * audio data BEFORE it goes to the speakers, allowing real-time
 * transcription without using the microphone.
 */
@OptIn(UnstableApi::class)
class CaptionAudioProcessor(
    private val onAudioData: (ByteArray) -> Unit
) : AudioProcessor {
    
    companion object {
        private const val TAG = "CaptionAudioProcessor"
        private const val TARGET_SAMPLE_RATE = 16000 // Vosk expects 16kHz
    }
    
    private var inputFormat = AudioFormat.NOT_SET
    private var outputFormat = AudioFormat.NOT_SET
    private var outputBuffer = AudioProcessor.EMPTY_BUFFER
    private var inputEnded = false
    private var isActive = false
    
    // Resampling state
    private var sampleRateRatio = 1.0f
    private var resampleBuffer: ShortArray = ShortArray(0)
    private var accumulatedSamples: ShortArray = ShortArray(0)
    
    override fun configure(inputAudioFormat: AudioFormat): AudioFormat {
        inputFormat = inputAudioFormat
        
        // We pass through the original format unchanged
        // but capture samples for speech recognition
        outputFormat = inputAudioFormat
        
        // Calculate resampling ratio
        if (inputAudioFormat.sampleRate > 0) {
            sampleRateRatio = TARGET_SAMPLE_RATE.toFloat() / inputAudioFormat.sampleRate
            isActive = inputAudioFormat.encoding == C.ENCODING_PCM_16BIT
            
            Log.d(TAG, "Configured: ${inputAudioFormat.sampleRate}Hz -> ${TARGET_SAMPLE_RATE}Hz, ratio=$sampleRateRatio, active=$isActive")
        }
        
        return outputFormat
    }
    
    override fun isActive(): Boolean = isActive
    
    override fun queueInput(inputBuffer: ByteBuffer) {
        if (!isActive || inputBuffer.remaining() == 0) {
            outputBuffer = inputBuffer
            return
        }
        
        try {
            // Copy input for processing (non-destructive)
            val inputCopy = ByteArray(inputBuffer.remaining())
            val position = inputBuffer.position()
            inputBuffer.get(inputCopy)
            inputBuffer.position(position) // Reset position for output
            
            // Convert to mono 16kHz for Vosk
            val processedAudio = processForSpeechRecognition(inputCopy)
            if (processedAudio.isNotEmpty()) {
                onAudioData(processedAudio)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing audio: ${e.message}")
        }
        
        // Pass through unchanged for playback
        outputBuffer = inputBuffer
    }
    
    private fun processForSpeechRecognition(audioData: ByteArray): ByteArray {
        if (audioData.isEmpty()) return ByteArray(0)
        
        // Convert bytes to shorts
        val shortCount = audioData.size / 2
        val inputSamples = ShortArray(shortCount)
        ByteBuffer.wrap(audioData).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(inputSamples)
        
        // Convert to mono if stereo
        val monoSamples = if (inputFormat.channelCount > 1) {
            convertToMono(inputSamples, inputFormat.channelCount)
        } else {
            inputSamples
        }
        
        // Resample to 16kHz if needed
        val resampledSamples = if (inputFormat.sampleRate != TARGET_SAMPLE_RATE) {
            resample(monoSamples, inputFormat.sampleRate, TARGET_SAMPLE_RATE)
        } else {
            monoSamples
        }
        
        // Convert back to bytes
        val result = ByteArray(resampledSamples.size * 2)
        ByteBuffer.wrap(result).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().put(resampledSamples)
        
        return result
    }
    
    private fun convertToMono(stereoSamples: ShortArray, channels: Int): ShortArray {
        val monoLength = stereoSamples.size / channels
        val mono = ShortArray(monoLength)
        
        for (i in 0 until monoLength) {
            var sum = 0
            for (ch in 0 until channels) {
                sum += stereoSamples[i * channels + ch]
            }
            mono[i] = (sum / channels).toShort()
        }
        
        return mono
    }
    
    private fun resample(input: ShortArray, srcRate: Int, dstRate: Int): ShortArray {
        val ratio = srcRate.toDouble() / dstRate
        val outputLength = (input.size / ratio).toInt()
        val output = ShortArray(outputLength)
        
        for (i in 0 until outputLength) {
            val srcIndex = (i * ratio).toInt()
            if (srcIndex < input.size) {
                output[i] = input[srcIndex]
            }
        }
        
        return output
    }
    
    override fun queueEndOfStream() {
        inputEnded = true
    }
    
    override fun getOutput(): ByteBuffer {
        val buffer = outputBuffer
        outputBuffer = AudioProcessor.EMPTY_BUFFER
        return buffer
    }
    
    override fun isEnded(): Boolean = inputEnded && outputBuffer == AudioProcessor.EMPTY_BUFFER
    
    override fun flush() {
        outputBuffer = AudioProcessor.EMPTY_BUFFER
        inputEnded = false
    }
    
    override fun reset() {
        flush()
        inputFormat = AudioFormat.NOT_SET
        outputFormat = AudioFormat.NOT_SET
        isActive = false
    }
}
