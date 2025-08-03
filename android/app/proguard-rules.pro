# ProGuard rules for MediaPipe and LLM (add keep rules as needed) 

# Keep all MediaPipe classes
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Keep all TensorFlow Lite classes
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Keep all Protobuf classes
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# Keep all AutoValue generated classes
-keep class com.google.auto.value.** { *; }
-dontwarn com.google.auto.value.**

# Keep javax.lang.model classes (annotation processing)
-dontwarn javax.lang.model.**

# Keep Flutter Gemma plugin classes
-keep class io.flutter.plugins.** { *; }

# Keep AI inference related classes
-keep class com.google.mediapipe.tasks.genai.** { *; }
-dontwarn com.google.mediapipe.tasks.genai.**

# Keep GPU delegate classes
-keep class org.tensorflow.lite.gpu.** { *; }
-dontwarn org.tensorflow.lite.gpu.**

# Prevent optimization of native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep all serializable classes for model loading
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep all annotation classes
-keep class * extends java.lang.annotation.Annotation
-keepattributes *Annotation*