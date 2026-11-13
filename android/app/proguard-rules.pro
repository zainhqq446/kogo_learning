# Keep Flutter engine, plugin registrant, and Android plugin classes invoked via JNI / reflection.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

-keep class xyz.luan.audioplayers.** { *; }
-keep class com.eyedeadevelopment.fluttertts.** { *; }
-keep class com.csdcorp.speech_to_text.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class com.github.dart_lang.jni.** { *; }

# Flutter embedding optional Play Core deferred-components references (not bundled unless deferred components are configured)
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
