# 保留ONNX Runtime的所有類
-keep class ai.onnxruntime.** { *; }

# 保留JNI方法
-keepclasseswithmembers class * {
    native <methods>;
}

# 保留ONNX Runtime原生庫相關的類
-keep class com.microsoft.onnxruntime.** { *; }

# 保留所有ONNX使用的外部庫
-keep public class * implements ai.onnxruntime.*
-keep class org.tensorflow.** { *; }

# 防止混淆可能影響動態加載的類
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable 