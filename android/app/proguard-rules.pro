# ── Crash reports ────────────────────────────────────────────────────────
# Keep line numbers so the Play Console can symbolicate a stack trace, but
# rename the source file attribute so the original file names aren't shipped.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ── Strip debug logging from release builds ──────────────────────────────
# The native side has ~90 Log.d/v/i calls that are useful during development
# and pure noise (and a small information leak — they print coordinates and
# prayer schedules) in a shipped build. R8 removes the calls and the string
# concatenation that feeds them. Log.w/e are deliberately kept: those are the
# ones worth having in a bug report.
-assumenosideeffects class android.util.Log {
    public static int d(...);
    public static int v(...);
    public static int i(...);
    public static boolean isLoggable(...);
}

# ── Flutter ──────────────────────────────────────────────────────────────
# The embedding is referenced reflectively by the generated registrant.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ── WorkManager ──────────────────────────────────────────────────────────
# PrayerUpdateWorker is instantiated by name from the WorkManager database,
# so nothing in the app statically references its constructor. Without this
# keep, a device that reboots with work already enqueued fails to start it.
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep class com.ki1lux.adhani.PrayerUpdateWorker { *; }

# ── App components reached only from the manifest / RemoteViews ──────────
# R8 keeps manifest-declared components, but the widget's RemoteViews and the
# alarm plumbing also cross process boundaries by name.
-keep class com.ki1lux.adhani.PrayerWidgetProvider { *; }
-keep class com.ki1lux.adhani.PrayerAlarmReceiver { *; }
-keep class com.ki1lux.adhani.BootReceiver { *; }
-keep class com.ki1lux.adhani.AdhanAlarmService { *; }
-keep class com.ki1lux.adhani.PrayerCountdownService { *; }

# ── Plugins with reflective entry points ─────────────────────────────────
-keep class com.baseflow.geolocator.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class xyz.luan.audioplayers.** { *; }
-keep class com.dexterous.** { *; }

# flutter_local_notifications deserialises its scheduled-notification state
# with Gson, so the field names of those model classes have to survive.
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keepclassmembers class com.dexterous.flutterlocalnotifications.models.** { <fields>; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature
-keepattributes *Annotation*

# ── Warnings from optional dependencies that are never on the classpath ──
-dontwarn com.google.android.play.core.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
