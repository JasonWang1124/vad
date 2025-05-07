# 解決Android上ONNX Runtime的動態庫載入問題

## 問題描述

在Android平台上運行時遇到以下錯誤：

```
Exception has occurred.
ArgumentError (Invalid argument(s): Failed to load dynamic library 'libonnxruntime.so': dlopen failed: library "libonnxruntime.so" not found)
```

這個問題是因為Android無法找到ONNX Runtime的動態庫文件（`libonnxruntime.so`）。

## 解決方案

我們已經通過以下步驟解決了這個問題：

### 1. 在Android項目中添加ONNX Runtime依賴

我們修改了 `example/android/app/build.gradle` 文件，添加了官方的ONNX Runtime Android依賴：

```gradle
dependencies {
    implementation 'com.microsoft.onnxruntime:onnxruntime-android:latest.release'
}
```

這會自動處理所有架構（arm64-v8a、armeabi-v7a、x86、x86_64）的庫文件。

### 2. 添加打包選項來處理可能的衝突

為了避免與其他庫可能存在的衝突，我們添加了以下配置：

```gradle
packagingOptions {
    pickFirst 'lib/arm64-v8a/libonnxruntime.so'
    pickFirst 'lib/armeabi-v7a/libonnxruntime.so'
    pickFirst 'lib/x86/libonnxruntime.so'
    pickFirst 'lib/x86_64/libonnxruntime.so'
}
```

### 3. 添加Proguard規則防止混淆

我們創建了 `example/android/app/proguard-rules.pro` 文件，內含以下規則：

```
# 保留ONNX Runtime的所有類
-keep class ai.onnxruntime.** { *; }
```

並在構建配置中啟用了這些規則：

```gradle
buildTypes {
    debug {
        minifyEnabled false
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
    
    release {
        signingConfig signingConfigs.debug
        minifyEnabled true
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
}
```

## 執行和測試

完成上述修改後，請執行以下操作：

1. 清理項目：
   ```
   flutter clean
   ```

2. 重新獲取依賴：
   ```
   flutter pub get
   ```

3. 重新構建Android應用：
   ```
   flutter run
   ```

## 可能的其他解決方案

如果上述方案不起作用，還可以嘗試其他幾種方法：

1. **手動下載預編譯的庫**：
   從 https://github.com/csukuangfj/onnxruntime-libs/releases 下載並提取相應的庫文件。

2. **從源代碼構建ONNX Runtime**：
   按照官方文檔 https://onnxruntime.ai/docs/build/android.html 構建自定義版本。

3. **檢查模型格式**：
   某些ONNX模型可能需要轉換為ORT格式以實現更好的兼容性，特別是對於移動平台。

## 參考資料

- [ONNX Runtime官方文檔](https://onnxruntime.ai/docs/install/)
- [Android上構建ONNX Runtime](https://onnxruntime.ai/docs/build/android.html)
- [Flutter與原生庫集成指南](https://flutter.dev/docs/development/platform-integration/android/c-interop) 