// vad_handler_web.dart

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'vad_handler_base.dart';

/// Start listening for voice activity detection (JS-binding)
@JS('startListeningImpl')
external void startListeningImpl(
    double positiveSpeechThreshold,
    double negativeSpeechThreshold,
    int preSpeechPadFrames,
    int redemptionFrames,
    int frameSamples,
    int minSpeechFrames,
    bool submitUserSpeechOnPause);

/// Stop listening for voice activity detection (JS-binding)
@JS('stopListeningImpl')
external void stopListeningImpl();

/// Check if the VAD is currently listening (JS-binding)
@JS('isListeningNow')
external bool isListeningNow();

/// Log a message to the console (JS-binding)
@JS('logMessage')
external void logMessage(String message);

/// Execute a Dart handler (JS-binding)
@JS('callDartFunction')
external void executeDartHandler();

/// VadHandlerWeb class
class VadHandlerWeb implements VadHandlerBase {
  final StreamController<List<double>> _onSpeechEndController =
      StreamController<List<double>>.broadcast();
  final StreamController<void> _onSpeechStartController =
      StreamController<void>.broadcast();
  final StreamController<void> _onVADMisfireController =
      StreamController<void>.broadcast();
  final StreamController<String> _onErrorController =
      StreamController<String>.broadcast();
  final StreamController<Uint8List> _onAudioFrameController =
      StreamController<Uint8List>.broadcast();
  final StreamController<void> _onSilenceController =
      StreamController<void>.broadcast();

  /// Whether to print debug messages
  bool isDebug = false;

  // 靜默檢測相關變數
  Timer? _silenceTimer;
  int _silenceThresholdSeconds = 5;
  DateTime _lastSpeechTime = DateTime.now();

  /// Constructor
  VadHandlerWeb({required bool isDebug}) {
    globalContext['executeDartHandler'] = handleEvent.toJS;
    isDebug = isDebug;
  }

  @override
  Stream<List<double>> get onSpeechEnd => _onSpeechEndController.stream;

  @override
  Stream<void> get onSpeechStart => _onSpeechStartController.stream;

  @override
  Stream<void> get onVADMisfire => _onVADMisfireController.stream;

  @override
  Stream<String> get onError => _onErrorController.stream;

  @override
  Stream<Uint8List> get onAudioFrame => _onAudioFrameController.stream;

  @override
  Stream<void> get onSilence => _onSilenceController.stream;

  /// 啟動靜默計時器
  void _startSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final silenceDuration = now.difference(_lastSpeechTime).inSeconds;

      if (silenceDuration >= _silenceThresholdSeconds) {
        // 用戶靜默時間超過閾值，發送事件
        _onSilenceController.add(null);
        if (isDebug) {
          debugPrint(
              'VadHandlerWeb: Silence detected after $_silenceThresholdSeconds seconds');
        }

        // 重置計時起點以避免連續發送過多事件
        _lastSpeechTime = now;
      }
    });
  }

  /// 重置靜默計時器
  void _resetSilenceTimer() {
    _lastSpeechTime = DateTime.now();
  }

  @override
  void startListening(
      {double positiveSpeechThreshold = 0.3,
      double negativeSpeechThreshold = 0.2,
      int preSpeechPadFrames = 2,
      int redemptionFrames = 12,
      int frameSamples = 1536,
      int minSpeechFrames = 2,
      bool submitUserSpeechOnPause = true,
      int warmupFrames = 10,
      int silenceThresholdSeconds = 5}) {
    if (isDebug) {
      debugPrint(
          'VadHandlerWeb: startListening: Calling startListeningImpl with parameters: '
          'positiveSpeechThreshold: $positiveSpeechThreshold, '
          'negativeSpeechThreshold: $negativeSpeechThreshold, '
          'preSpeechPadFrames: $preSpeechPadFrames, '
          'redemptionFrames: $redemptionFrames, '
          'frameSamples: $frameSamples, '
          'minSpeechFrames: $minSpeechFrames, '
          'submitUserSpeechOnPause: $submitUserSpeechOnPause, '
          'warmupFrames: $warmupFrames, '
          'silenceThresholdSeconds: $silenceThresholdSeconds');
    }

    // 設置靜默閾值
    _silenceThresholdSeconds = silenceThresholdSeconds;

    // 重置並啟動靜默計時器
    _resetSilenceTimer();
    _startSilenceTimer();

    startListeningImpl(
        positiveSpeechThreshold,
        negativeSpeechThreshold,
        preSpeechPadFrames,
        redemptionFrames,
        frameSamples,
        minSpeechFrames,
        submitUserSpeechOnPause);
  }

  /// Handle an event from the JS side
  void handleEvent(String eventType, String payload) {
    try {
      Map<String, dynamic> eventData =
          payload.isNotEmpty ? json.decode(payload) : {};

      switch (eventType) {
        case 'onError':
          if (isDebug) {
            debugPrint('VadHandlerWeb: onError: ${eventData['error']}');
          }
          _onErrorController.add(payload);
          break;
        case 'onSpeechEnd':
          if (eventData.containsKey('audioData')) {
            final List<double> audioData = (eventData['audioData'] as List)
                .map((e) => (e as num).toDouble())
                .toList();
            if (isDebug) {
              debugPrint(
                  'VadHandlerWeb: onSpeechEnd: first 5 samples: ${audioData.sublist(0, 5)}');
            }
            _onSpeechEndController.add(audioData);
          } else {
            if (isDebug) {
              debugPrint('Invalid VAD Data received: $eventData');
            }
          }
          // 重置靜默計時器，用戶剛剛結束說話
          _resetSilenceTimer();
          break;
        case 'onSpeechStart':
          if (isDebug) {
            debugPrint('VadHandlerWeb: onSpeechStart');
          }
          _onSpeechStartController.add(null);
          // 重置靜默計時器，用戶開始說話
          _resetSilenceTimer();
          break;
        case 'onVADMisfire':
          if (isDebug) {
            debugPrint('VadHandlerWeb: onVADMisfire');
          }
          _onVADMisfireController.add(null);
          break;
        case 'onAudioFrame':
          if (eventData.containsKey('audioData')) {
            final List<int> audioDataList = (eventData['audioData'] as List)
                .map((e) => (e as num).toInt())
                .toList();
            final Uint8List audioData = Uint8List.fromList(audioDataList);
            if (isDebug) {
              debugPrint(
                  'VadHandlerWeb: onAudioFrame: ${audioData.length} bytes');
            }
            _onAudioFrameController.add(audioData);
          }
          break;
        default:
          debugPrint("Unknown event: $eventType");
      }
    } catch (e, st) {
      debugPrint('Error handling event: $e');
      debugPrint('$st');
    }
  }

  @override
  void dispose() {
    if (isDebug) {
      debugPrint('VadHandlerWeb: dispose');
    }
    // 取消靜默計時器
    _silenceTimer?.cancel();
    _silenceTimer = null;

    _onSpeechEndController.close();
    _onSpeechStartController.close();
    _onVADMisfireController.close();
    _onErrorController.close();
    _onAudioFrameController.close();
    _onSilenceController.close();
  }

  @override
  void stopListening() {
    if (isDebug) {
      debugPrint('VadHandlerWeb: stopListening');
    }
    // 取消靜默計時器
    _silenceTimer?.cancel();
    _silenceTimer = null;

    stopListeningImpl();
  }
}

/// Create a VAD handler for the web
/// isDebug is used to print debug messages
/// modelPath is not used in the web implementation, adding it will not have any effect
VadHandlerBase createVadHandler({required isDebug, modelPath}) =>
    VadHandlerWeb(isDebug: isDebug);
