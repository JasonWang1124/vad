// lib/main.dart

import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'dart:async'; // 添加 Timer 支持
import 'package:permission_handler/permission_handler.dart';
import 'package:vad/vad.dart';
import 'package:vad_example/recording.dart';
import 'package:vad_example/vad_settings_dialog.dart';
import 'package:vad_example/ui/vad_ui.dart';
import 'package:vad_example/ui/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VAD Example',
      theme: AppTheme.getDarkTheme(),
      home: const VadManager(),
    );
  }
}

class VadManager extends StatefulWidget {
  const VadManager({super.key});

  @override
  State<VadManager> createState() => _VadManagerState();
}

class _VadManagerState extends State<VadManager> {
  List<Recording> recordings = [];
  late VadHandlerBase _vadHandler;
  bool isListening = false;
  bool isSpeechDetected = false;
  late VadSettings settings;
  final VadUIController _uiController = VadUIController();

  int currentVolumeLevel = 0;
  double currentDecibels = 0.0;

  // 靜音檢測相關變量
  Timer? _silenceTimer;
  bool _isSilent = true;
  DateTime? _silenceStartTime;
  bool _isVadInitialized = false; // 新增：追蹤VAD是否已初始化

  // 持續錄音模式初始化狀態
  bool _isContinuousRecordingInitializing = false;

  // 靜音閥值回調
  final _onSilenceThresholdReachedController =
      StreamController<DateTime>.broadcast();
  Stream<DateTime> get onSilenceThresholdReached =>
      _onSilenceThresholdReachedController.stream;

  @override
  void initState() {
    super.initState();
    settings = VadSettings();
    _initializeVad();
  }

  void _initializeVad() {
    // 記錄是否為第一次初始化
    bool isFirstInit = !_isVadInitialized;

    // 如果已經初始化過，先釋放資源
    if (_isVadInitialized) {
      _vadHandler.dispose();
    }

    _vadHandler = VadHandler.create(isDebug: true);
    _setupVadHandler();
    _isVadInitialized = true;

    // 只在第一次初始化時設定預設值
    if (isFirstInit) {
      setState(() {
        settings = settings.copy()
          ..positiveSpeechThreshold = 0.8 // 降低正向閾值（原為0.5）
          ..negativeSpeechThreshold = 0.2 // 降低負向閾值（原為0.35）
          ..minSpeechFrames = 10 // 減少最小語音幀數（原為8）
          ..redemptionFrames = 15 // 增加贖回幀數（提高容錯度）
          ..model = RecordingModel.v5;
      });
    }

    // 重置所有狀態
    setState(() {
      isSpeechDetected = false;
      _isSilent = true;
      _silenceStartTime = DateTime.now();
    });
  }

  void _startListening() {
    _resetSilenceDetection(); // 重置靜音檢測

    _vadHandler.startListening(
      frameSamples: settings.frameSamples,
      minSpeechFrames: settings.minSpeechFrames,
      preSpeechPadFrames: settings.preSpeechPadFrames,
      redemptionFrames: settings.redemptionFrames,
      positiveSpeechThreshold: settings.positiveSpeechThreshold,
      negativeSpeechThreshold: settings.negativeSpeechThreshold,
      submitUserSpeechOnPause: settings.submitUserSpeechOnPause,
      model: settings.modelString,
      baseAssetPath: 'packages/vad/assets/',
      onnxWASMBasePath: 'packages/vad/assets/',
      audioGain: settings.audioGain,
      realtimeGainEnabled: settings.realtimeGainEnabled,
      saveOriginalAudio: settings.saveOriginalAudio,
    );
    setState(() {
      isListening = true;
      isSpeechDetected = false;
    });

    // 啟動靜音計時器
    _startSilenceTimer();
  }

  void _stopListening() {
    _stopSilenceTimer(); // 停止靜音計時器

    _vadHandler.stopListening();
    setState(() {
      isListening = false;
      isSpeechDetected = false;
    });

    // 確保在停止時重置所有相關狀態
    _resetSilenceDetection();
  }

  Future<void> _manualStopWithAudio() async {
    if (isListening && isSpeechDetected) {
      final audioData = await _vadHandler.manualStopWithAudio();
      if (audioData != null) {
        setState(() {
          recordings.add(Recording(
            samples: audioData,
            type: RecordingType.manualStop,
          ));
          isListening = false;
          isSpeechDetected = false;
        });
        _uiController.scrollToBottom?.call();
        debugPrint('Speech manually stopped, recording added.');
      } else {
        _stopListening();
      }
    } else {
      _stopListening();
    }
  }

  void _setupVadHandler() {
    _vadHandler.onSpeechStart.listen((_) {
      setState(() {
        recordings.add(Recording(
          samples: [],
          type: RecordingType.speechStart,
        ));
        isSpeechDetected = true;
      });
      _uiController.scrollToBottom?.call();
      debugPrint('Speech detected.');

      // 更新靜音狀態
      _isSilent = false;
      _resetSilenceDetection();
    });

    _vadHandler.onRealSpeechStart.listen((_) {
      setState(() {
        recordings.add(Recording(
          samples: [],
          type: RecordingType.realSpeechStart,
        ));
      });
      _uiController.scrollToBottom?.call();
      debugPrint('Real speech start detected.');
    });

    _vadHandler.onSpeechEnd.listen((List<double> samples) {
      setState(() {
        recordings.add(Recording(
          samples: samples,
          type: RecordingType.speechEnd,
        ));
        isSpeechDetected = false;
      });
      _uiController.scrollToBottom?.call();
      debugPrint('Speech ended, recording added.');
    });

    _vadHandler.onVADMisfire.listen((_) {
      setState(() {
        recordings.add(Recording(type: RecordingType.misfire));
        isSpeechDetected = false;
      });
      _uiController.scrollToBottom?.call();
      debugPrint('VAD misfire detected.');

      // 只重置狀態，不停止服務
      _resetSilenceDetection();
    });

    _vadHandler.onFrameProcessed.listen((frameData) {
      final isSpeech = frameData.isSpeech;
      final notSpeech = frameData.notSpeech;
      final decibels = frameData.decibels;
      final volumeLevel = frameData.volumeLevel;

      setState(() {
        currentVolumeLevel = volumeLevel;
        currentDecibels = decibels;
      });

      // 靜音檢測邏輯
      if (isListening) {
        if (isSpeech > settings.positiveSpeechThreshold) {
          // 檢測到語音，重置靜音計時
          if (_isSilent) {
            _isSilent = false;
            _resetSilenceDetection();
          }
        } else if (isSpeech < settings.negativeSpeechThreshold) {
          // 檢測到靜音
          if (!_isSilent) {
            _isSilent = true;
            _silenceStartTime = DateTime.now();
          }
        }
      }

      debugPrint(
          'Frame processed - isSpeech: $isSpeech, notSpeech: $notSpeech, decibels: $decibels, volumeLevel: $volumeLevel');
    });

    _vadHandler.onError.listen((String message) {
      setState(() {
        recordings.add(Recording(type: RecordingType.error));
      });
      _uiController.scrollToBottom?.call();
      debugPrint('Error: $message');
    });
  }

  void _applySettings(
      VadSettings newSettings, bool wasContinuousMode, bool wasVadProcessing) {
    // 強制根據模型同步 frameSamples
    if (newSettings.model == RecordingModel.legacy) {
      newSettings.frameSamples = 1536;
    } else {
      newSettings.frameSamples = 512;
    }

    bool wasListening = isListening;

    // 如果正在監聽，先停止
    if (wasListening) {
      _stopListening();
    }

    // 更新設定
    setState(() {
      settings = newSettings;
    });

    // 重新初始化 VAD
    _initializeVad();

    // 根據之前的狀態決定如何重新啟動
    if (wasContinuousMode) {
      // 重新啟用持續錄音模式
      _enableContinuousRecording().then((_) {
        // 如果之前 VAD 處理是啟用的，重新啟用
        if (wasVadProcessing) {
          _quickStartVad();
        }
      });

      debugPrint('設定已應用：重新啟用持續錄音模式 (VAD處理: $wasVadProcessing)');
    } else if (wasListening) {
      // 傳統模式，如果之前在監聽就重新開始
      _startListening();
      debugPrint('設定已應用：重新啟動傳統監聽模式');
    }

    debugPrint('Settings applied: $newSettings');
  }

  /// 設定對話框取消時的處理
  void _onSettingsDialogCancel(bool wasContinuousMode, bool wasVadProcessing) {
    // 如果之前是持續錄音模式，恢復該模式
    if (wasContinuousMode) {
      _enableContinuousRecording().then((_) {
        // 如果之前 VAD 處理是啟用的，重新啟用
        if (wasVadProcessing) {
          _quickStartVad();
        }
      });

      debugPrint('設定對話框已取消：恢復持續錄音模式 (VAD處理: $wasVadProcessing)');
    }
  }

  /// 啟用持續錄音模式 - 實現幾乎 0 冷啟動
  Future<void> _enableContinuousRecording() async {
    if (_isVadInitialized) {
      try {
        // 設置初始化狀態
        setState(() {
          _isContinuousRecordingInitializing = true;
        });

        debugPrint('開始啟用持續錄音模式...');

        // 設置持續錄音模式
        _vadHandler.setContinuousRecordingMode(true);

        // 給VAD一點時間來處理模式變更
        await Future.delayed(const Duration(milliseconds: 100));

        // 啟動音訊流但停用 VAD 處理
        _vadHandler.startListening(
          frameSamples: settings.frameSamples,
          minSpeechFrames: settings.minSpeechFrames,
          preSpeechPadFrames: settings.preSpeechPadFrames,
          redemptionFrames: settings.redemptionFrames,
          positiveSpeechThreshold: settings.positiveSpeechThreshold,
          negativeSpeechThreshold: settings.negativeSpeechThreshold,
          submitUserSpeechOnPause: settings.submitUserSpeechOnPause,
          model: settings.modelString,
          baseAssetPath: 'packages/vad/assets/',
          onnxWASMBasePath: 'packages/vad/assets/',
          audioGain: settings.audioGain,
          realtimeGainEnabled: settings.realtimeGainEnabled,
          saveOriginalAudio: settings.saveOriginalAudio,
        );

        // 給音訊流更多時間來完全初始化
        await Future.delayed(const Duration(milliseconds: 10));

        // 停用 VAD 處理，只保持音訊流
        _vadHandler.setVadProcessingEnabled(false);

        // 再次延遲確保狀態完全設置
        // await Future.delayed(const Duration(milliseconds: 100));

        // 驗證狀態是否正確設置
        bool continuousMode = _vadHandler.isContinuousRecordingMode;
        bool vadProcessing = _vadHandler.isVadProcessingEnabled;

        debugPrint('狀態驗證 - 持續錄音: $continuousMode, VAD處理: $vadProcessing');

        // 如果狀態不正確，再次嘗試設置
        if (!continuousMode) {
          debugPrint('重新設置持續錄音模式...');
          _vadHandler.setContinuousRecordingMode(true);
          await Future.delayed(const Duration(milliseconds: 100));
        }

        if (vadProcessing) {
          debugPrint('重新停用VAD處理...');
          _vadHandler.setVadProcessingEnabled(false);
          await Future.delayed(const Duration(milliseconds: 100));
        }

        // 最終狀態更新
        setState(() {
          isListening = false; // UI 顯示為未監聽狀態
        });

        // 驗證最終狀態並強制UI更新
        if (mounted) {
          await Future.delayed(const Duration(milliseconds: 100));

          // 使用專門的狀態同步方法
          _validateAndSyncVadState();

          // 再次延遲確保狀態完全同步
          await Future.delayed(const Duration(milliseconds: 50));
          _validateAndSyncVadState();
        }

        debugPrint('持續錄音模式已啟用 - 音訊流保持活躍，VAD 處理已停用');

        // 清除初始化狀態
        setState(() {
          _isContinuousRecordingInitializing = false;
        });
      } catch (e) {
        debugPrint('啟用持續錄音模式時發生錯誤: $e');
        // 確保UI狀態一致
        setState(() {
          isListening = false;
          _isContinuousRecordingInitializing = false; // 清除初始化狀態
        });
      }
    } else {
      debugPrint('VAD 尚未初始化，無法啟用持續錄音模式');
      // 確保初始化狀態正確
      setState(() {
        _isContinuousRecordingInitializing = false;
      });
    }
  }

  /// 快速啟動 VAD 處理（幾乎 0 冷啟動）
  void _quickStartVad() {
    if (_isVadInitialized && _vadHandler.isContinuousRecordingMode) {
      // 直接啟用 VAD 處理，無需重新啟動音訊流
      _vadHandler.setVadProcessingEnabled(true);

      setState(() {
        isListening = true;
        isSpeechDetected = false;
      });

      // 啟動靜音計時器
      _startSilenceTimer();

      // 同步狀態確保UI正確更新
      Future.delayed(const Duration(milliseconds: 50), () {
        _validateAndSyncVadState();
      });

      debugPrint('VAD 處理已快速啟動 - 幾乎 0 冷啟動！');
    } else {
      // 回退到傳統啟動方式
      _startListening();
    }
  }

  /// 快速停止 VAD 處理（保持音訊流）
  void _quickStopVad() {
    if (_isVadInitialized && _vadHandler.isContinuousRecordingMode) {
      // 只停用 VAD 處理，保持音訊流
      _vadHandler.setVadProcessingEnabled(false);

      setState(() {
        isListening = false;
        isSpeechDetected = false;
      });

      _stopSilenceTimer();
      _resetSilenceDetection();

      // 同步狀態確保UI正確更新
      Future.delayed(const Duration(milliseconds: 50), () {
        _validateAndSyncVadState();
      });

      debugPrint('VAD 處理已快速停止 - 音訊流保持活躍');
    } else {
      // 回退到傳統停止方式
      _stopListening();
    }
  }

  /// 完全停止持續錄音模式
  Future<void> _disableContinuousRecording() async {
    if (_isVadInitialized) {
      try {
        _vadHandler.setContinuousRecordingMode(false);

        // 給一點時間來處理模式變更
        await Future.delayed(const Duration(milliseconds: 50));

        _stopListening(); // 完全停止音訊流

        debugPrint('持續錄音模式已停用');
      } catch (e) {
        debugPrint('停用持續錄音模式時發生錯誤: $e');
        // 確保狀態一致
        _stopListening();
      }
    }
  }

  void _showSettingsDialog() {
    // 如果處於持續錄音模式，先停止以避免狀態衝突
    bool wasContinuousMode = false;
    bool wasVadProcessing = false;

    if (_isVadInitialized && _vadHandler.isContinuousRecordingMode) {
      wasContinuousMode = true;
      wasVadProcessing = _vadHandler.isVadProcessingEnabled;

      // 暫時停止持續錄音模式
      _disableContinuousRecording();
      debugPrint('設定對話框開啟：暫時停止持續錄音模式');
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return VadSettingsDialog(
          settings: settings,
          onSettingsChanged: (newSettings) =>
              _applySettings(newSettings, wasContinuousMode, wasVadProcessing),
          onCancel: () =>
              _onSettingsDialogCancel(wasContinuousMode, wasVadProcessing),
        );
      },
    );
  }

  Future<void> _requestMicrophonePermission() async {
    if (Platform.isWindows) {
      debugPrint("在Windows平台上不需要麥克風權限請求，繼續操作");
      return;
    }

    final status = await Permission.microphone.request();
    debugPrint("Microphone permission status: $status");
  }

  @override
  Widget build(BuildContext context) {
    return VadUI(
      recordings: recordings,
      isListening: isListening,
      isSpeechDetected: isSpeechDetected,
      volumeLevel: currentVolumeLevel,
      decibels: currentDecibels,
      settings: settings,
      onStartListening: _startListening,
      onStopListening: _stopListening,
      onManualStopWithAudio: _manualStopWithAudio,
      onRequestMicrophonePermission: _requestMicrophonePermission,
      onShowSettingsDialog: _showSettingsDialog,
      controller: _uiController,

      // 持續錄音模式控制回調
      onEnableContinuousRecording: _enableContinuousRecording,
      onQuickStartVad: _quickStartVad,
      onQuickStopVad: _quickStopVad,
      onDisableContinuousRecording: _disableContinuousRecording,
      isContinuousRecordingMode:
          _isVadInitialized ? _vadHandler.isContinuousRecordingMode : false,
      isVadProcessingEnabled:
          _isVadInitialized ? _vadHandler.isVadProcessingEnabled : true,
      isContinuousRecordingInitializing: _isContinuousRecordingInitializing,
    );
  }

  @override
  void dispose() {
    if (isListening) {
      _vadHandler.stopListening();
    }
    _vadHandler.dispose();
    _uiController.dispose();
    _stopSilenceTimer();
    _onSilenceThresholdReachedController.close();
    super.dispose();
  }

  // 啟動靜音計時器
  void _startSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!isListening || isSpeechDetected) return;

      if (_isSilent && _silenceStartTime != null) {
        final silenceDuration = DateTime.now().difference(_silenceStartTime!);
        if (silenceDuration.inMilliseconds >=
            settings.silenceThresholdSeconds * 1000) {
          // 靜音閥值達到
          _onSilenceThresholdReachedController.add(DateTime.now());

          // 將檢測到的靜音事件添加到錄音列表中
          setState(() {
            recordings.add(Recording(
              samples: [],
              type: RecordingType.silenceThresholdReached,
            ));
          });
          _uiController.scrollToBottom?.call();

          // 重置靜音檢測
          _resetSilenceDetection();

          debugPrint('靜音閥值達到: ${settings.silenceThresholdSeconds}秒');
        }
      }
    });
  }

  // 停止靜音計時器
  void _stopSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  // 重置靜音檢測
  void _resetSilenceDetection() {
    _isSilent = true;
    _silenceStartTime = DateTime.now();
  }

  /// 驗證並同步VAD狀態，確保UI顯示正確
  void _validateAndSyncVadState() {
    if (_isVadInitialized && mounted) {
      // 強制UI重建以反映最新的VAD狀態
      setState(() {
        // 這個setState會觸發UI重建，確保isContinuousRecordingMode和isVadProcessingEnabled的最新值被讀取
      });

      debugPrint(
          'VAD狀態已同步 - 持續錄音: ${_vadHandler.isContinuousRecordingMode}, VAD處理: ${_vadHandler.isVadProcessingEnabled}');
    }
  }
}
