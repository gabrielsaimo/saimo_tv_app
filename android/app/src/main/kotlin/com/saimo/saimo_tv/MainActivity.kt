package com.saimo.saimo_tv

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register Vosk caption plugin
        flutterEngine.plugins.add(VoskCaptionPlugin())
    }
}
