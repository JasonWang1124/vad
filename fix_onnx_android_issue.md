# 解決VAD Android應用ONNX原生庫提取問題

## 問題描述

執行Flutter應用時遇到以下錯誤：

```
Error: ADB exited with exit code 1
Performing Streamed Install

adb: failed to install [...]/app-debug.apk: Failure [INSTALL_FAILED_INVALID_APK: INSTALL_FAILED_INVALID_APK: Failed to extract native libraries, res=-2]
Error launching application on sdk gphone16k x86 64.
```

此錯誤表示Android無法正確提取APK中的原生庫（ONNX Runtime的libonnxruntime.so）。

## 解決方案

核心解決方案是修改`android/app/build.gradle`檔案，確保ONNX Runtime正確整合：

```gradle
android {
    // 基本設定保持不變...
    
    // 添加ONNX Runtime支持
    packagingOptions {
        pickFirst 'lib/arm64-v8a/libonnxruntime.so'
        pickFirst 'lib/armeabi-v7a/libonnxruntime.so'
        pickFirst 'lib/x86/libonnxruntime.so'
        pickFirst 'lib/x86_64/libonnxruntime.so'
    }
}

flutter {
    source = "../.."
}

// 添加ONNX Runtime依賴
dependencies {
    // 使用自動版本選擇，讓系統選擇兼容的版本
    implementation 'com.microsoft.onnxruntime:onnxruntime-android:+'
}
```

## 解決步驟

1. 修改`android/app/build.gradle`檔案，加入上述設定
2. 確保AndroidManifest.xml中設置了`android:extractNativeLibs="true"`：
   ```xml
   <application
       android:label="vad_example"
       android:name="${applicationName}"
       android:extractNativeLibs="true"
       android:icon="@mipmap/ic_launcher">
   ```
3. 清理並重新運行專案：
   ```
   flutter clean
   flutter pub get
   flutter run
   ```

## 避免的錯誤

在解決這類問題時，應避免：

1. ❌ 過度修改build.gradle檔案
2. ❌ 添加複雜的原生庫配置
3. ❌ 手動下載並放置.so檔案
4. ❌ 設置過多的ProGuard規則

## 最佳實踐

1. ✅ 使用自動版本選擇`+`，讓系統選擇合適的ONNX版本
2. ✅ 只添加必要的packagingOptions設定
3. ✅ 確保AndroidManifest.xml中開啟原生庫提取
4. ✅ 遵循最小干預原則，一次只修改一個變數

這個解決方案適用於類似的Flutter應用集成ONNX Runtime的場景，特別是在遇到原生庫提取問題時。 