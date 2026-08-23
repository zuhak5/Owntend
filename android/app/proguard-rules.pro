# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-dontwarn io.flutter.**
-dontwarn com.google.android.play.core.**

# WorkManager uses Room-generated classes through reflection during
# AndroidX Startup initialization. Keep those implementations intact in
# minified release builds so the app can launch before Flutter starts.
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.model.** { *; }
-keep class androidx.room.** { *; }
-keep class androidx.sqlite.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }

# Google Mobile Ads SDK and Native Ad Factory
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.mediation.** { *; }
-keep class app.owntend.mobile.OwntendNativeAdFactory { *; }

# flutter_foreground_task plugin
-keep class com.pravera.flutter_foreground_task.** { *; }
-dontwarn com.pravera.flutter_foreground_task.**

# androidx media3 / ExoPlayer (audioplayers)
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
