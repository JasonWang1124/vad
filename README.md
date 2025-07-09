# VAD - 語音活動檢測 Flutter 套件

VAD 是一個支援 **iOS**、**Android**、**Web** 和 **Windows** 平台的 Flutter 語音活動檢測 (Voice Activity Detection) 函式庫。此套件讓應用程式能夠啟動和停止基於 VAD 的語音監聽，並無縫處理各種 VAD 事件。

在底層實作上，VAD 套件在 Web 平台使用 `dart:js_interop` 來執行 [VAD JavaScript 函式庫](https://github.com/ricky0123/vad)，在 iOS、Android 和 Windows 平台則使用 [onnxruntime](https://github.com/gtbluesky/onnxruntime_flutter) 來運行 onnxruntime 函式庫，提供與 JavaScript 函式庫完全相同的功能。

此套件提供簡潔的 API 來啟動和停止 VAD 監聽、設定 VAD 參數，並處理各種 VAD 事件，如語音開始、語音結束、錯誤和誤觸發等。

## 目錄
<!-- TOC start -->

- [VAD - 語音活動檢測 Flutter 套件](#vad---語音活動檢測-flutter-套件)
    * [目錄](#目錄)
    * [線上展示](#線上展示)
    * [功能特色](#功能特色)
    * [新增功能](#新增功能)
        + [即時音訊增益](#即時音訊增益)
        + [持續錄音模式（幾乎 0 冷啟動）](#持續錄音模式幾乎-0-冷啟動)
        + [智慧設定管理](#智慧設定管理)
        + [Windows 平台支援](#windows-平台支援)
    * [開始使用](#開始使用)
        + [先決條件](#先決條件)
            - [Web](#web)
            - [iOS](#ios)
            - [Android](#android)
            - [Windows](#windows)
    * [安裝](#安裝)
    * [使用方法](#使用方法)
        + [基本範例](#基本範例)
        + [進階功能使用](#進階功能使用)
            - [即時增益功能](#即時增益功能)
            - [持續錄音模式](#持續錄音模式)
    * [VadHandler API](#vadhandler-api)
        + [方法](#方法)
            - [`create`](#create)
            - [`startListening`](#startlistening)
            - [`stopListening`](#stoplistening)
            - [`dispose`](#dispose)
            - [新增的持續錄音方法](#新增的持續錄音方法)
        + [事件](#事件)
            - [`onSpeechEnd`](#onspeechend)
            - [`onSpeechStart`](#onspeechstart)
            - [`onRealSpeechStart`](#onrealspeechstart)
            - [`onVADMisfire`](#onvadmisfire)
            - [`onFrameProcessed`](#onframeprocessed)
            - [`onError`](#onerror)
    * [權限設定](#權限設定)
        + [iOS](#ios-1)
        + [Android](#android-1)
        + [Web](#web-1)
        + [Windows](#windows-1)
    * [資源清理](#資源清理)
    * [測試平台](#測試平台)
    * [貢獻](#貢獻)
    * [致謝](#致謝)
    * [授權](#授權)

<!-- TOC end -->

## 線上展示
查看 [VAD 套件範例應用程式](https://keyur2maru.github.io/vad/) 以在 Web 平台上體驗 VAD 套件的實際運作。

## 功能特色

- **跨平台支援：** 在 iOS、Android、Web 和 Windows 上無縫運作
- **事件串流：** 監聽語音開始、實際語音開始、語音結束、語音誤觸發、幀處理和錯誤等事件
- **Silero V4 和 V5 模型：** 支援 Silero VAD v4 和 v5 模型
- **即時音訊增益：** 在麥克風收音階段即時放大音訊訊號
- **持續錄音模式：** 實現幾乎 0 冷啟動的快速語音檢測
- **智慧設定管理：** 自動處理設定變更和狀態恢復

## 新增功能

### 即時音訊增益
在傳統模式中，音訊增益是在 VAD 處理後才應用到輸出音訊上。新的即時增益功能可以在麥克風收音階段就放大音訊訊號，提供更好的訊號品質。

**特色：**
- 智慧增益控制，避免音訊失真
- 軟壓縮算法防止削波
- 可動態開啟/關閉

### 持續錄音模式（幾乎 0 冷啟動）
革命性的持續錄音功能讓音訊流保持活躍狀態，只需控制 VAD 處理的開啟/關閉，實現幾乎瞬間的語音檢測啟動。

**效能提升：**
- 傳統啟動：~500-1000ms
- 持續模式：~10-50ms（95% 時間減少）

**架構優勢：**
```
傳統模式: 啟動 → 音訊流 + VAD → 停止 → 關閉音訊流
持續模式: 音訊流常駐 → VAD 開關 → 幾乎 0 冷啟動
```

### 智慧設定管理
當在持續錄音模式下修改設定時，系統會自動：
1. 暫停持續錄音模式
2. 應用新設定
3. 智慧恢復到之前的運行狀態

### Windows 平台支援
完整支援 Windows 平台，包括：
- 原生 Windows 音訊 API 整合
- 自動權限處理
- 完整的 VAD 功能支援

## 開始使用

### 先決條件

在將 VAD 套件整合到您的 Flutter 應用程式之前，請確保您已為每個目標平台進行了必要的設定。

#### Web
要在 Web 上使用 VAD，請在 `web/index.html` 檔案的 head 和 body 標籤中分別包含以下腳本來載入必要的 VAD 函式庫：

```html
<head>
  ...
  <script src="assets/packages/vad/assets/ort.js"></script>
  ...
</head>
...
<body>
...
<script src="assets/packages/vad/assets/bundle.min.js" defer></script>
<script src="assets/packages/vad/assets/vad_web.js" defer></script>
...
</body>
```

您也可以參考 [VAD 範例應用程式](https://github.com/keyur2maru/vad/blob/master/example/web/index.html) 的完整範例。

**提示：啟用 WASM 多執行緒 (SharedArrayBuffer) 可獲得 10 倍效能提升**

* 生產環境請在伺服器回應中發送以下標頭：
  ```html
  Cross-Origin-Embedder-Policy: require-corp
  Cross-Origin-Opener-Policy: same-origin
  ```

* 本地開發請參考範例應用程式 GitHub Pages 展示頁面中應用的解決方案。

#### iOS
對於 iOS，您需要在 `Info.plist` 檔案中設定麥克風權限和其他設定。

1. **添加麥克風使用說明：** 開啟 `ios/Runner/Info.plist` 並添加以下條目來請求麥克風存取權限：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>此應用程式需要存取麥克風以進行語音活動檢測。</string>
```

2. **設定建置設定：** 確保您的 `Podfile` 包含麥克風權限所需的建置設定：

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_MICROPHONE=1',
      ]
    end
  end
end
```

#### Android
對於 Android，請在您的 `AndroidManifest.xml` 和 `build.gradle` 檔案中設定所需的權限和建置設定。

1. **添加權限：** 開啟 `android/app/src/main/AndroidManifest.xml` 並添加以下權限：

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
```

2. **設定建置設定：** 開啟 `android/app/build.gradle` 並添加以下設定：
```gradle
android {
    compileSdkVersion 34
    ...
}
```

#### Windows
對於 Windows 平台，系統會自動處理麥克風權限。確保您的應用程式在 Windows 10/11 上運行。

## 安裝
將 VAD 套件添加到您的 `pubspec.yaml` 相依性中：

```yaml
dependencies:
  flutter:
    sdk: flutter
  vad: ^0.0.5
  permission_handler: ^11.3.1
```

然後執行 `flutter pub get` 來獲取套件。

## 使用方法

### 基本範例

以下是一個簡單的範例，展示如何在 Flutter 應用程式中整合和使用 VAD 套件。

```dart
// main.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vad/vad.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text("VAD 範例")),
        body: const MyHomePage(),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _vadHandler = VadHandler.create(isDebug: true);
  bool isListening = false;
  final List<String> receivedEvents = [];

  @override
  void initState() {
    super.initState();
    _setupVadHandler();
  }

  void _setupVadHandler() {
    _vadHandler.onSpeechStart.listen((_) {
      debugPrint('檢測到語音。');
      setState(() {
        receivedEvents.add('檢測到語音。');
      });
    });

    _vadHandler.onSpeechEnd.listen((List<double> samples) {
      debugPrint('語音結束，前 10 個樣本：${samples.take(10).toList()}');
      setState(() {
        receivedEvents.add('語音結束，前 10 個樣本：${samples.take(10).toList()}');
      });
    });

    _vadHandler.onError.listen((String message) {
      debugPrint('錯誤：$message');
      setState(() {
        receivedEvents.add('錯誤：$message');
      });
    });
  }

  @override
  void dispose() {
    _vadHandler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            onPressed: () async {
              setState(() {
                if (isListening) {
                  _vadHandler.stopListening();
                } else {
                  _vadHandler.startListening();
                }
                isListening = !isListening;
              });
            },
            icon: Icon(isListening ? Icons.stop : Icons.mic),
            label: Text(isListening ? "停止監聽" : "開始監聽"),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: receivedEvents.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(receivedEvents[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
```

### 進階功能使用

#### 即時增益功能

```dart
// 啟動監聽時啟用即時增益
_vadHandler.startListening(
  audioGain: 2.0,              // 音訊增益倍率
  realtimeGainEnabled: true,   // 啟用即時增益
);

// 動態切換即時增益
_vadHandler.setRealtimeGainEnabled(true);
```

#### 持續錄音模式

```dart
// 啟用持續錄音模式
_vadHandler.setContinuousRecordingMode(true);

// 啟動音訊流（但不啟動 VAD 處理）
_vadHandler.startListening();
_vadHandler.setVadProcessingEnabled(false);

// 快速啟動 VAD 處理（幾乎 0 冷啟動）
_vadHandler.setVadProcessingEnabled(true);

// 快速停止 VAD 處理（保持音訊流）
_vadHandler.setVadProcessingEnabled(false);

// 完全停止持續錄音模式
_vadHandler.setContinuousRecordingMode(false);
```

## VadHandler API

### 方法

#### `create`
建立一個新的 `VadHandler` 實例，可選擇啟用除錯模式。

#### `startListening`
使用可設定的參數啟動 VAD。

**新增參數：**
- `audioGain`: 音訊增益倍率（預設：1.0）
- `realtimeGainEnabled`: 是否啟用即時增益（預設：false）

```dart
void startListening({
  double positiveSpeechThreshold = 0.5,
  double negativeSpeechThreshold = 0.35,
  int preSpeechPadFrames = 1,
  int redemptionFrames = 8,
  int frameSamples = 1536,
  int minSpeechFrames = 3,
  bool submitUserSpeechOnPause = false,
  String model = 'legacy',
  String baseAssetPath = 'assets/packages/vad/assets/',
  String onnxWASMBasePath = 'assets/packages/vad/assets/',
  double audioGain = 1.0,
  bool realtimeGainEnabled = false,
});
```

#### `stopListening`
停止 VAD 會話。

#### `dispose`
釋放 VadHandler 並關閉所有串流。

#### 新增的持續錄音方法

```dart
// 設定持續錄音模式
void setContinuousRecordingMode(bool enabled);
bool get isContinuousRecordingMode;

// 控制 VAD 處理
void setVadProcessingEnabled(bool enabled);
bool get isVadProcessingEnabled;

// 控制即時增益
void setRealtimeGainEnabled(bool enabled);
bool get isRealtimeGainEnabled;
```

### 事件

#### `onSpeechEnd`
當檢測到語音結束時觸發，提供音訊樣本。

#### `onSpeechStart`
當檢測到語音開始時觸發。

#### `onRealSpeechStart`
當確認實際語音時觸發（超過最小幀數閾值）。

#### `onVADMisfire`
當最初檢測到語音但未達到最小語音幀數閾值時觸發。

#### `onFrameProcessed`
在處理每個音訊幀後觸發，提供語音機率和原始音訊資料。

#### `onError`
當發生錯誤時觸發。

## 權限設定

正確處理麥克風權限對於 VAD 套件在所有平台上正常運作至關重要。

### iOS
- **設定：** 確保在您的 `Info.plist` 中添加 `NSMicrophoneUsageDescription`
- **執行時權限：** 使用 `permission_handler` 套件在執行時請求麥克風權限

### Android
- **設定：** 在您的 `AndroidManifest.xml` 中添加 `RECORD_AUDIO`、`MODIFY_AUDIO_SETTINGS` 和 `INTERNET` 權限
- **執行時權限：** 使用 `permission_handler` 套件在執行時請求麥克風權限

### Web
- **瀏覽器權限：** 麥克風存取由瀏覽器管理，當 VAD 開始監聽時會提示使用者授予麥克風存取權限

### Windows
- **自動處理：** Windows 平台會自動處理麥克風權限，無需額外設定

## 資源清理

為了防止記憶體洩漏並確保所有資源都得到適當釋放，在不再需要 `VadHandler` 實例時，請務必呼叫 `dispose` 方法。

```dart
vadHandler.dispose();
```

## 測試平台

VAD 套件已在以下平台上進行測試：

- **iOS：** 在運行 iOS 18.1 的 iPhone 15 Pro Max 上測試
- **Android：** 在運行 Android 10 的 Lenovo Tab M8 上測試
- **Web：** 在 Chrome Mac/Windows/Android/iOS、Safari Mac/iOS 上測試
- **Windows：** 在 Windows 10/11 上測試

## 貢獻

歡迎貢獻！如果您遇到任何問題或有改進建議，請隨時提交 pull request 或開啟 issue。

## 致謝

特別感謝 [Ricky0123](https://github.com/ricky0123) 創建了 [VAD JavaScript 函式庫](https://github.com/ricky0123/vad)，[gtbluesky](https://github.com/gtbluesky) 建立了 [onnxruntime 套件](https://github.com/gtbluesky/onnxruntime_flutter)，以及 Silero 團隊提供了函式庫中使用的 [VAD 模型](https://github.com/snakers4/silero-vad)。

## 授權

本專案採用 [MIT 授權](https://opensource.org/license/mit)。詳細資訊請參閱 [LICENSE](https://github.com/TBD-JasonWang/vad/blob/master/LICENSE) 檔案。

---

如有任何問題或想要貢獻，請造訪 [GitHub 儲存庫](https://github.com/TBD-JasonWang/vad)。