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
    _vadHandler = VadHandler.create(isDebug: true);
    _setupVadHandler();
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
      baseAssetPath: 'assets/packages/vad/assets/',
      onnxWASMBasePath: 'assets/packages/vad/assets/',
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

    _vadHandler.onFrameProcessed.listen((frameData) {
      final isSpeech = frameData.isSpeech;
      final notSpeech = frameData.notSpeech;
      final decibels = frameData.decibels;
      final volumeLevel = frameData.volumeLevel;
      final firstFiveSamples = frameData.frame.length >= 5
          ? frameData.frame.sublist(0, 5)
          : frameData.frame;

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
      debugPrint('First few audio samples: $firstFiveSamples');
    });

    _vadHandler.onVADMisfire.listen((_) {
      setState(() {
        recordings.add(Recording(type: RecordingType.misfire));
      });
      _uiController.scrollToBottom?.call();
      debugPrint('VAD misfire detected.');
    });

    _vadHandler.onError.listen((String message) {
      setState(() {
        recordings.add(Recording(type: RecordingType.error));
      });
      _uiController.scrollToBottom?.call();
      debugPrint('Error: $message');
    });
  }

  void _applySettings(VadSettings newSettings) {
    bool wasListening = isListening;

    if (isListening) {
      _vadHandler.stopListening();
      isListening = false;
    }

    setState(() {
      settings = newSettings;
    });

    _vadHandler.dispose();
    _initializeVad();

    if (wasListening) {
      _startListening();
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return VadSettingsDialog(
          settings: settings,
          onSettingsChanged: _applySettings,
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
}
