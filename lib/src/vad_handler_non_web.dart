// vad_handler_non_web.dart

import 'package:flutter/cupertino.dart';
import 'package:record/record.dart';
import 'package:vad/src/vad_handler_base.dart';
import 'package:vad/src/vad_iterator.dart';
import 'dart:async';
import 'vad_event.dart';
import 'vad_iterator_base.dart';
import 'dart:math';

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

  /// Default Silero VAD Legacy (v4) model path (used for non-web)
  static const String vadLegacyModelPath = 'lib/assets/silero_vad_legacy.onnx';

  /// Default Silero VAD V5 model path (used for non-web)
  static const String vadV5ModelPath = 'lib/assets/silero_vad_v5.onnx';

  final _onSpeechEndController = StreamController<List<double>>.broadcast();
  final _onFrameProcessedController = StreamController<
      ({
        double isSpeech,
        double notSpeech,
        List<double> frame,
        double decibels,
        int volumeLevel
      })>.broadcast();
  final _onSpeechStartController = StreamController<void>.broadcast();
  final _onRealSpeechStartController = StreamController<void>.broadcast();
  final _onVADMisfireController = StreamController<void>.broadcast();
  final _onErrorController = StreamController<String>.broadcast();

  @override
  Stream<List<double>> get onSpeechEnd => _onSpeechEndController.stream;

  @override
  Stream<
      ({
        double isSpeech,
        double notSpeech,
        List<double> frame,
        double decibels,
        int volumeLevel
      })> get onFrameProcessed => _onFrameProcessedController.stream;

  @override
  Stream<void> get onSpeechStart => _onSpeechStartController.stream;

  @override
  Stream<void> get onRealSpeechStart => _onRealSpeechStartController.stream;

  @override
  Stream<void> get onVADMisfire => _onVADMisfireController.stream;

  @override
  Stream<String> get onError => _onErrorController.stream;

  /// Constructor
  VadHandlerNonWeb({required this.isDebug, this.modelPath = ''});

  /// 軟壓縮/軟限幅算法，比clamp更溫和，減少失真
  double _softClip(double sample, double gain) {
    // 應用增益
    double amplifiedSample = sample * gain;

    // 使用軟限幅方法，保留更多動態範圍
    if (amplifiedSample.abs() > 0.8) {
      return (amplifiedSample.abs() / amplifiedSample) *
          (1.0 - exp(-3.0 * amplifiedSample.abs()));
    }

    // 對於較小的值，保持線性，以保持原始的動態範圍
    return amplifiedSample;
  }

  /// 預分析音訊以找到最佳增益值，避免嚴重失真
  double _getOptimalGain(List<double> samples, double requestedGain) {
    if (requestedGain <= 1.0) return requestedGain; // 小於1的增益不需要優化

    // 找出音訊樣本中的最大絕對值
    double maxAmp = 0.0;
    for (var sample in samples) {
      maxAmp = maxAmp < sample.abs() ? sample.abs() : maxAmp;
    }

    // 如果最大值乘以增益會超過0.95，則調整增益
    // 0.95作為安全邊界，避免極端接近1.0
    if (maxAmp * requestedGain > 0.95) {
      // 計算一個安全的增益值，但最低不小於原始值的70%
      // 這樣可以保證有放大效果，但避免嚴重失真
      double safeGain = 0.95 / maxAmp;
      return max(safeGain, requestedGain * 0.7);
    }

    return requestedGain;
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
        break;
      case VadEventType.realStart:
        _onRealSpeechStartController.add(null);
        break;
      case VadEventType.end:
        if (event.audioData != null && _isInitialized) {
          final int16List = event.audioData!.buffer.asInt16List();

          // 先轉換回浮點數樣本
          final rawSamples = int16List.map((e) => e / 32768.0).toList();

          // 分析並求最佳增益值
          final optimalGain =
              _getOptimalGain(rawSamples, _vadIterator.audioGain);
          if (isDebug && optimalGain != _vadIterator.audioGain) {
            debugPrint(
                'Adjusted gain from ${_vadIterator.audioGain.toStringAsFixed(2)} to ${optimalGain.toStringAsFixed(2)} to reduce distortion');
          }

          // 應用軟壓縮和優化後的增益
          final floatSamples =
              rawSamples.map((e) => _softClip(e, optimalGain)).toList();

          _onSpeechEndController.add(floatSamples);
        }
        break;
      case VadEventType.frameProcessed:
        if (event.probabilities != null && event.frameData != null) {
          _onFrameProcessedController.add((
            isSpeech: event.probabilities!.isSpeech,
            notSpeech: event.probabilities!.notSpeech,
            frame: event.frameData!,
            decibels: event.probabilities!.decibels,
            volumeLevel: event.probabilities!.volumeLevel
          ));
        }
        break;
      case VadEventType.misfire:
        _onVADMisfireController.add(null);
        break;
      case VadEventType.error:
        _onErrorController.add(event.message);
        break;
    }
  }

  @override
  Future<void> startListening(
      {double positiveSpeechThreshold = 0.5,
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
      bool realtimeGainEnabled = false}) async {
    try {
      if (!_isInitialized) {
        if (isDebug) debugPrint('VadHandlerNonWeb: 初始化 VAD');
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
          model: model,
          audioGain: audioGain,
        );

        // 設定模型路徑 - 總是根據當前模型重新設定
        String baseModelPath;
        if (model == 'v5') {
          baseModelPath = 'silero_vad_v5.onnx';
        } else {
          baseModelPath = 'silero_vad_legacy.onnx';
        }

        // 嘗試標準包路徑格式 (這會在 pubspec.yaml 中的資源設定下工作)
        modelPath = 'packages/vad/assets/$baseModelPath';

        if (isDebug) debugPrint('VadHandlerNonWeb: 設定模型路徑為: $modelPath');

        if (isDebug) debugPrint('VadHandlerNonWeb: 使用模型路徑: $modelPath');

        try {
          await _vadIterator.initModel(modelPath);
          if (isDebug) debugPrint('VadHandlerNonWeb: 模型初始化成功');
        } catch (modelError) {
          if (isDebug) debugPrint('VadHandlerNonWeb: 模型初始化失敗: $modelError');
          _onErrorController.add('VadHandlerNonWeb: 模型初始化失敗: $modelError');
          rethrow;
        }

        _vadIterator.setVadEventCallback(_handleVadEvent);
        _submitUserSpeechOnPause = submitUserSpeechOnPause;
        _isInitialized = true;
      } else {
        // 如果已經初始化，重置 VAD 狀態並更新音訊增益
        _vadIterator.reset();
        _vadIterator.audioGain = audioGain;
        if (isDebug) debugPrint('VadHandlerNonWeb: 重置 VAD 狀態');
      }

      // 設定即時增益
      _vadIterator.setRealtimeGainEnabled(realtimeGainEnabled);
      if (isDebug) {
        debugPrint(
            'VadHandlerNonWeb: 即時增益${realtimeGainEnabled ? "已啟用" : "已停用"}');
      }

      // 檢查錄音權限
      if (isDebug) debugPrint('VadHandlerNonWeb: 檢查錄音權限');
      bool hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        const errorMsg = 'VadHandlerNonWeb: 沒有錄音權限';
        if (isDebug) debugPrint(errorMsg);
        _onErrorController.add(errorMsg);
        return;
      }

      // 開始錄音流
      if (isDebug) debugPrint('VadHandlerNonWeb: 開始錄音流');
      final stream = await _audioRecorder.startStream(const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          bitRate: 16,
          numChannels: 1,
          echoCancel: true,
          autoGain: true,
          noiseSuppress: true));

      _audioStreamSubscription = stream.listen(
        (data) async {
          await _vadIterator.processAudioData(data);
        },
        onError: (e) {
          if (isDebug) debugPrint('VadHandlerNonWeb: 錄音流錯誤: $e');
          _onErrorController.add('錄音流錯誤: $e');
        },
      );

      if (isDebug) debugPrint('VadHandlerNonWeb: 開始偵測語音');
    } catch (e) {
      if (isDebug) debugPrint('VadHandlerNonWeb: startListening 異常: $e');
      _onErrorController.add('初始化語音偵測時發生錯誤: $e');
      rethrow;
    }
  }

  /// Enable or disable real-time gain application
  @override
  void setRealtimeGainEnabled(bool enabled) {
    if (_isInitialized) {
      _vadIterator.setRealtimeGainEnabled(enabled);
      if (isDebug) {
        debugPrint('VadHandlerNonWeb: 即時增益${enabled ? "已啟用" : "已停用"}');
      }
    }
  }

  /// Get current real-time gain status
  @override
  bool get isRealtimeGainEnabled {
    return _isInitialized ? _vadIterator.isRealtimeGainEnabled : false;
  }

  @override
  Future<void> stopListening() async {
    if (isDebug) debugPrint('stopListening');
    try {
      // 確保只有在已初始化的情況下才訪問_vadIterator
      if (_isInitialized) {
        // Before stopping the audio stream, handle forced speech end if needed
        if (_submitUserSpeechOnPause) {
          _vadIterator.forceEndSpeech();
        }
        _vadIterator.reset();
      }

      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;
      await _audioRecorder.stop();
    } catch (e) {
      _onErrorController.add(e.toString());
      if (isDebug) debugPrint('Error stopping audio stream: $e');
    }
  }

  /// Manually stop speech detection and get audio data
  @override
  Future<List<double>?> manualStopWithAudio() async {
    if (isDebug) debugPrint('manualStopWithAudio');
    try {
      // 確保只有在已初始化的情況下才訪問_vadIterator
      if (!_isInitialized) {
        return null;
      }

      // Get audio data from the VAD iterator
      final audioData = await _vadIterator.manualEndSpeech();

      // Stop listening
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;
      await _audioRecorder.stop();
      _vadIterator.reset();

      return audioData;
    } catch (e) {
      _onErrorController.add(e.toString());
      if (isDebug) debugPrint('Error manually stopping with audio: $e');
      return null;
    }
  }

  @override
  void dispose() {
    if (isDebug) debugPrint('VadHandlerNonWeb: dispose');
    try {
      stopListening();
      // 確保只有在已初始化的情況下才訪問_vadIterator
      if (_isInitialized) {
        _vadIterator.release();
        _isInitialized = false; // 重置初始化標誌
      }

      // 重置模型路徑，強制重新初始化
      modelPath = '';
    } catch (e) {
      if (isDebug) debugPrint('Error disposing VAD handler: $e');
    } finally {
      _onSpeechEndController.close();
      _onFrameProcessedController.close();
      _onSpeechStartController.close();
      _onRealSpeechStartController.close();
      _onVADMisfireController.close();
      _onErrorController.close();
    }
  }
}

/// Create a VAD handler for the non-web platforms
VadHandlerBase createVadHandler({required isDebug, modelPath}) =>
    VadHandlerNonWeb(isDebug: isDebug, modelPath: modelPath);
