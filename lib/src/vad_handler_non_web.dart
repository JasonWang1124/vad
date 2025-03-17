// vad_handler_non_web.dart
import 'package:flutter/cupertino.dart';
import 'package:record/record.dart';
import 'package:vad/src/vad_handler_base.dart';
import 'package:vad/src/vad_iterator.dart';
import 'dart:async';
import 'dart:typed_data';
import 'vad_event.dart';
import 'vad_iterator_base.dart';

/// VadHandlerNonWeb class
class VadHandlerNonWeb implements VadHandlerBase {
  final AudioRecorder _audioRecorder = AudioRecorder();
  late VadIteratorBase _vadIterator;
  StreamSubscription<List<int>>? _audioStreamSubscription;

  /// Path to the model file
  String modelPath;

  /// Debug flag
  bool isDebug = false;
  bool _isInitialized = false;
  bool _submitUserSpeechOnPause = false;

  /// Sample rate
  static const int sampleRate = 16000;

  final _onSpeechEndController = StreamController<List<double>>.broadcast();
  final _onSpeechStartController = StreamController<void>.broadcast();
  final _onVADMisfireController = StreamController<void>.broadcast();
  final _onErrorController = StreamController<String>.broadcast();
  final _onAudioFrameController = StreamController<Uint8List>.broadcast();
  final _onSilenceController = StreamController<void>.broadcast();

  // 靜默檢測相關變數
  Timer? _silenceTimer;
  int _silenceThresholdSeconds = 5;
  DateTime _lastSpeechTime = DateTime.now();

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

  /// Constructor
  VadHandlerNonWeb(
      {required this.isDebug,
      this.modelPath = 'packages/vad/assets/models/silero_vad.onnx'});

  /// 啟動靜默計時器
  void _startSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final silenceDuration = now.difference(_lastSpeechTime).inSeconds;

      if (silenceDuration >= _silenceThresholdSeconds) {
        // 用戶靜默時間超過閾值，發送事件
        _onSilenceController.add(null);
        if (isDebug) {
          debugPrint(
              'VadHandlerNonWeb: Silence detected after $_silenceThresholdSeconds seconds');
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

  /// Handle VAD event
  void _handleVadEvent(VadEvent event) {
    if (isDebug) {
      debugPrint(
          'VadHandlerNonWeb: VAD Event: ${event.type} with message ${event.message}');
    }
    switch (event.type) {
      case VadEventType.start:
        _onSpeechStartController.add(null);
        // 重置靜默計時器，因為檢測到用戶開始說話
        _resetSilenceTimer();
        break;
      case VadEventType.end:
        if (event.audioData != null) {
          final int16List = event.audioData!.buffer.asInt16List();
          final floatSamples = int16List.map((e) => e / 32768.0).toList();
          _onSpeechEndController.add(floatSamples);
        }
        // 重置靜默計時器，檢測到用戶剛剛結束說話
        _resetSilenceTimer();
        break;
      case VadEventType.misfire:
        _onVADMisfireController.add(null);
        break;
      case VadEventType.error:
        _onErrorController.add(event.message);
        break;
      case VadEventType.audioFrame:
        if (event.audioData != null) {
          _onAudioFrameController.add(event.audioData!);
        }
        break;
      default:
        break;
    }
  }

  @override
  Future<void> startListening(
      {double positiveSpeechThreshold = 0.3,
      double negativeSpeechThreshold = 0.2,
      int preSpeechPadFrames = 2,
      int redemptionFrames = 12,
      int frameSamples = 1536,
      int minSpeechFrames = 2,
      bool submitUserSpeechOnPause = true,
      int warmupFrames = 10,
      int silenceThresholdSeconds = 5}) async {
    if (!_isInitialized) {
      _vadIterator = VadIterator.create(
          isDebug: isDebug,
          sampleRate: sampleRate,
          frameSamples: frameSamples,
          positiveSpeechThreshold: positiveSpeechThreshold,
          negativeSpeechThreshold: negativeSpeechThreshold,
          redemptionFrames: redemptionFrames,
          preSpeechPadFrames: preSpeechPadFrames,
          minSpeechFrames: minSpeechFrames,
          submitUserSpeechOnPause: submitUserSpeechOnPause,
          warmupFrames: warmupFrames);
      await _vadIterator.initModel(modelPath);
      _vadIterator.setVadEventCallback(_handleVadEvent);
      _submitUserSpeechOnPause = submitUserSpeechOnPause;
      _isInitialized = true;
    } else {
      // 如果已經初始化，更新參數
      _submitUserSpeechOnPause = submitUserSpeechOnPause;
      _vadIterator.setWarmupFrames(warmupFrames);
    }

    // 設置靜默閾值
    _silenceThresholdSeconds = silenceThresholdSeconds;

    bool hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      _onErrorController
          .add('VadHandlerNonWeb: No permission to record audio.');
      if (isDebug) {
        debugPrint('VadHandlerNonWeb: No permission to record audio.');
      }
      return;
    }

    // 重置並啟動靜默計時器
    _resetSilenceTimer();
    _startSilenceTimer();

    // Start recording with a stream
    final stream = await _audioRecorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        bitRate: 16,
        numChannels: 1,
        echoCancel: true,
        autoGain: true,
        noiseSuppress: true));

    _audioStreamSubscription = stream.listen((data) async {
      await _vadIterator.processAudioData(data);
    });
  }

  @override
  Future<void> stopListening() async {
    if (isDebug) debugPrint('stopListening');
    try {
      // 停止靜默計時器
      _silenceTimer?.cancel();
      _silenceTimer = null;

      // Before stopping the audio stream, handle forced speech end if needed
      if (_submitUserSpeechOnPause && _vadIterator.isSpeaking()) {
        _vadIterator.forceEndSpeech();
      }

      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;
      await _audioRecorder.stop();
      _vadIterator.reset();
    } catch (e) {
      _onErrorController.add(e.toString());
      if (isDebug) debugPrint('Error stopping audio stream: $e');
    }
  }

  @override
  void dispose() {
    if (isDebug) debugPrint('VadHandlerNonWeb: dispose');
    stopListening();
    _vadIterator.release();
    _onSpeechEndController.close();
    _onSpeechStartController.close();
    _onVADMisfireController.close();
    _onErrorController.close();
    _onAudioFrameController.close();
    _onSilenceController.close();
  }
}

/// Create a VAD handler for the non-web platforms
VadHandlerBase createVadHandler({required isDebug, modelPath}) =>
    VadHandlerNonWeb(isDebug: isDebug, modelPath: modelPath);
