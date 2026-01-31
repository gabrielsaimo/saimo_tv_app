package com.saimo.saimo_tv

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var audioCapturePlugin: AudioCapturePlugin? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize audio capture plugin for CC
        audioCapturePlugin = AudioCapturePlugin(flutterEngine)
    }
    
    override fun onDestroy() {
        audioCapturePlugin?.dispose()
        audioCapturePlugin = null
        super.onDestroy()
    }
}
