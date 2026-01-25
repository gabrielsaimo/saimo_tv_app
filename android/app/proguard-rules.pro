# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Prevent obfuscation of specific classes if needed (e.g. Models mapped from JSON)
# -keep class com.saimo.tv.models.** { *; }

# Video Player
-keep class com.google.android.exoplayer2.** { *; }

# WebView (if used)
-keep class android.webkit.** { *; }

# Ignore Play Store Dynamic Features (not used)
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
