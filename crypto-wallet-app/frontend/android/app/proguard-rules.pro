# Flutter specific ProGuard rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep crypto libraries
-keep class org.bouncycastle.** { *; }
-keep class org.web3j.** { *; }
-keep class com.nftco.flow.** { *; }

# Keep SharedPreferences for secure storage
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }

# Keep biometric authentication
-keep class androidx.biometric.** { *; }

# Keep QR code scanner
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }

# Keep local notifications
-keep class com.dexterous.** { *; }

# Keep audioplayers
-keep class xyz.luan.audioplayers.** { *; }

# Retrofit/OkHttp (for Dio)
-keepattributes Signature
-keepattributes *Annotation*
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Gson
-keep class com.google.gson.** { *; }
-keepattributes *Annotation*

# Prevent stripping of native libraries
-keep class * extends java.lang.Exception
-keepclassmembers class * {
    native <methods>;
}

# Keep line numbers for crash reports
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# MILITARY-GRADE: Remove ALL logging in release builds
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
    public static int e(...);
    public static int wtf(...);
}

# Remove System.out/err logging
-assumenosideeffects class java.io.PrintStream {
    public void println(...);
    public void print(...);
}

# MILITARY-GRADE: Maximum obfuscation settings
-optimizationpasses 5
-allowaccessmodification
-repackageclasses ''
-flattenpackagehierarchy
-dontpreverify

# Protect against reflection attacks
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Play Core library (for deferred components)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Secure storage - keep encrypted preferences
-keep class androidx.security.crypto.EncryptedSharedPreferences { *; }
-keep class androidx.security.crypto.MasterKey { *; }
-keep class androidx.security.crypto.MasterKey$Builder { *; }
