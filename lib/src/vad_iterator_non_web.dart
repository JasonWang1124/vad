import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:vad/src/vad_iterator_base.dart';

import 'vad_event.dart';

/// Voice Activity Detection (VAD) iterator for real-time audio processing.
class VadIteratorNonWeb implements VadIteratorBase {
  /// Debug flag to enable/disable logging.
  bool isDebug = false;

  /// Threshold for positive speech detection.
  double positiveSpeechThreshold = 0.5;

  /// Threshold for negative speech detection.
  double negativeSpeechThreshold = 0.35;

  /// Number of frames for redemption after speech detection.
  int redemptionFrames = 8;

  /// Number of samples in a frame.
  /// Default is 1536 samples for 96ms at 16kHz sample rate.
  /// * > WARNING! Silero VAD models were trained using 512, 1024, 1536 samples for 16000 sample rate and 256, 512, 768 samples for 8000 sample rate.
  /// * > Values other than these may affect model perfomance!!
  /// * In this context, audio fed to the VAD model always has sample rate 16000. It is probably a good idea to leave this at 1536.
  int frameSamples = 1536;

  /// Number of frames to pad before speech detection.
  int preSpeechPadFrames = 1;

  /// Minimum number of speech frames to consider as valid speech.
  int minSpeechFrames = 3;

  /// Sample rate of the audio data.
  int sampleRate = 16000;

  /// Flag to submit user speech on pause/stop event.
  bool submitUserSpeechOnPause = false;

  /// Model name
  /// * 'legacy' for Silero VAD Legacy model
  /// * 'v5' for Silero VAD v5 model
  String model;

  /// Audio gain to apply to output audio samples
  double _audioGain = 1.0;

  /// Whether to apply gain in real-time (before VAD processing)
  bool _realtimeGainEnabled = false;

  /// Whether VAD processing is enabled (can be toggled while audio stream continues)
  bool _vadProcessingEnabled = true;

  /// Whether continuous recording mode is enabled
  bool _continuousRecordingMode = false;

  @override
  double get audioGain => _audioGain;

  @override
  set audioGain(double value) {
    _audioGain = value;
  }

  /// Enable or disable real-time gain application
  @override
  void setRealtimeGainEnabled(bool enabled) {
    _realtimeGainEnabled = enabled;
    if (isDebug) {
      debugPrint('Real-time gain ${enabled ? "enabled" : "disabled"}');
    }
  }

  /// Get current real-time gain status
  @override
  bool get isRealtimeGainEnabled => _realtimeGainEnabled;

  /// Enable or disable VAD processing while keeping audio stream active
  @override
  void setVadProcessingEnabled(bool enabled) {
    _vadProcessingEnabled = enabled;
    if (isDebug) {
      debugPrint('VAD processing ${enabled ? "enabled" : "disabled"}');
    }
  }

  /// Get current VAD processing status
  @override
  bool get isVadProcessingEnabled => _vadProcessingEnabled;

  /// Enable continuous recording mode (audio stream always active)
  @override
  void setContinuousRecordingMode(bool enabled) {
    _continuousRecordingMode = enabled;
    if (isDebug) {
      debugPrint(
          'Continuous recording mode ${enabled ? "enabled" : "disabled"}');
    }
  }

  /// Get continuous recording mode status
  @override
  bool get isContinuousRecordingMode => _continuousRecordingMode;

  // Internal variables
  /// Flag to indicate speech detection state.
  bool speaking = false;

  /// Counter for speech redemption frames.
  int redemptionCounter = 0;

  /// Counter for positive speech frames.
  int speechPositiveFrameCount = 0;
  int _currentSample = 0; // To track position in samples

  /// Buffers for pre-speech and speech data.
  List<Float32List> preSpeechBuffer = [];

  /// Buffer for speech data.
  List<Float32List> speechBuffer = [];

  // Model variables
  OrtSessionOptions? _sessionOptions;
  OrtSession? _session;

  // Model states
  static const int _batch = 1;
  var _hide = List.filled(
      2, List.filled(_batch, Float32List.fromList(List.filled(64, 0.0))));
  var _cell = List.filled(
      2, List.filled(_batch, Float32List.fromList(List.filled(64, 0.0))));
  var _state = List.filled(
      2, List.filled(_batch, Float32List.fromList(List.filled(128, 0.0))));

  /// Callback for VAD events.
  VadEventCallback? onVadEvent;

  /// Byte buffer for audio data.
  final List<int> _byteBuffer = [];

  /// Size of a frame in bytes.
  int frameByteCount;

  /// Create a new VAD iterator.
  VadIteratorNonWeb({
    required this.isDebug,
    required this.sampleRate,
    required this.frameSamples,
    required this.positiveSpeechThreshold,
    required this.negativeSpeechThreshold,
    required this.redemptionFrames,
    required this.preSpeechPadFrames,
    required this.minSpeechFrames,
    required this.submitUserSpeechOnPause,
    required this.model,
    double audioGain = 1.0,
  }) : frameByteCount = frameSamples * 2 {
    _audioGain = audioGain;
  }

  /// Initialize the VAD model from the given [modelPath].
  @override
  Future<void> initModel(String modelPath) async {
    try {
      if (isDebug) debugPrint('VAD: 初始化模型，路徑: $modelPath');

      _sessionOptions = OrtSessionOptions()
        ..setInterOpNumThreads(1)
        ..setIntraOpNumThreads(1)
        ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

      // 可能的路徑格式列表，將依次嘗試
      final possiblePaths = <String>[];

      // 1. 原始路徑
      possiblePaths.add(modelPath);

      // 2. 處理包路徑格式
      if (modelPath.startsWith('packages/vad/assets/')) {
        // 2.1 轉換為 lib/assets 格式
        possiblePaths
            .add(modelPath.replaceAll('packages/vad/assets/', 'lib/assets/'));

        // 2.2 轉換為絕對路徑格式
        possiblePaths.add('assets/${modelPath.split('/').last}');

        // 2.3 Android 特殊格式
        possiblePaths.add(modelPath.replaceAll('packages/', ''));
      } else {
        // 3. 處理非包路徑格式
        final fileName = modelPath.split('/').last;

        // 3.1 嘗試包路徑格式
        possiblePaths.add('packages/vad/assets/$fileName');

        // 3.2 嘗試 lib/assets 格式
        possiblePaths.add('lib/assets/$fileName');

        // 3.3 嘗試絕對路徑格式
        possiblePaths.add('assets/$fileName');

        // 3.4 處理相對路徑情況
        if (!modelPath.contains('/')) {
          possiblePaths.add('lib/assets/$modelPath');
          possiblePaths.add('assets/$modelPath');
        }
      }

      // 移除重複路徑
      final uniquePaths = possiblePaths.toSet().toList();

      if (isDebug) {
        debugPrint('VAD: 將嘗試以下路徑：');
        for (var path in uniquePaths) {
          debugPrint('  - $path');
        }
      }

      // 儲存最後發生的錯誤，以便在全部嘗試失敗時重新拋出
      dynamic lastError;

      // 依次嘗試每個可能的路徑
      for (var path in uniquePaths) {
        try {
          if (isDebug) debugPrint('VAD: 嘗試載入路徑: $path');
          final rawAssetFile = await rootBundle.load(path);
          final bytes = rawAssetFile.buffer.asUint8List();
          _session = OrtSession.fromBuffer(bytes, _sessionOptions!);
          if (isDebug) debugPrint('VAD: 成功從路徑初始化模型: $path');

          // 模型載入成功後，根據模型類型初始化正確的狀態
          _initializeModelStates();

          return; // 成功後立即返回
        } catch (e) {
          if (isDebug) debugPrint('VAD: 路徑 $path 載入失敗: $e');
          lastError = e;
          // 繼續嘗試下一個路徑
        }
      }

      // 所有路徑都嘗試失敗
      throw lastError ?? Exception('無法載入模型，所有可能的路徑均失敗');
    } catch (e) {
      final errorMessage = 'VAD model initialization failed: $e';
      debugPrint(errorMessage);
      onVadEvent?.call(VadEvent(
        type: VadEventType.error,
        timestamp: _getCurrentTimestamp(),
        message: errorMessage,
      ));
      rethrow;
    }
  }

  /// Initialize model states based on the model type
  void _initializeModelStates() {
    if (model == 'v5') {
      // v5 模型使用不同的狀態結構
      _state = List.filled(
          2, List.filled(_batch, Float32List.fromList(List.filled(128, 0.0))));
      if (isDebug) debugPrint('VAD: 初始化 v5 模型狀態');
    } else {
      // Legacy 模型使用 _hide 和 _cell
      _hide = List.filled(
          2, List.filled(_batch, Float32List.fromList(List.filled(64, 0.0))));
      _cell = List.filled(
          2, List.filled(_batch, Float32List.fromList(List.filled(64, 0.0))));
      if (isDebug) debugPrint('VAD: 初始化 legacy 模型狀態');
    }
  }

  /// Reset the VAD iterator.
  @override
  void reset() {
    speaking = false;
    redemptionCounter = 0;
    speechPositiveFrameCount = 0;
    _currentSample = 0;
    preSpeechBuffer.clear();
    speechBuffer.clear();
    _byteBuffer.clear();

    // 根據模型類型重置狀態
    if (model == 'v5') {
      _state = List.filled(
          2, List.filled(_batch, Float32List.fromList(List.filled(128, 0.0))));
    } else {
      _hide = List.filled(
          2, List.filled(_batch, Float32List.fromList(List.filled(64, 0.0))));
      _cell = List.filled(
          2, List.filled(_batch, Float32List.fromList(List.filled(64, 0.0))));
      _state = List.filled(
          2, List.filled(_batch, Float32List.fromList(List.filled(128, 0.0))));
    }
  }

  /// Release the VAD iterator resources.
  @override
  void release() {
    _sessionOptions?.release();
    _sessionOptions = null;
    _session?.release();
    _session = null;
    OrtEnv.instance.release();
  }

  /// Set the VAD event callback.
  @override
  void setVadEventCallback(VadEventCallback callback) {
    onVadEvent = callback;
  }

  /// Process audio data.
  @override
  Future<void> processAudioData(List<int> data) async {
    _byteBuffer.addAll(data);

    while (_byteBuffer.length >= frameByteCount) {
      final frameBytes = _byteBuffer.sublist(0, frameByteCount);
      _byteBuffer.removeRange(0, frameByteCount);

      final frameData = _convertBytesToFloat32(Uint8List.fromList(frameBytes));

      // 如果啟用即時增益，在 VAD 處理前應用增益
      final processedFrameData =
          _realtimeGainEnabled ? _applyRealtimeGain(frameData) : frameData;

      // 只有在 VAD 處理啟用時才進行 VAD 分析
      if (_vadProcessingEnabled) {
        await _processFrame(Float32List.fromList(processedFrameData));
      } else {
        // VAD 處理停用時，仍然發送原始音訊幀事件（用於監控或其他用途）
        _emitRawFrameEvent(Float32List.fromList(processedFrameData));
      }
    }
  }

  /// Apply real-time gain to audio frame before VAD processing
  List<double> _applyRealtimeGain(List<double> frameData) {
    if (_audioGain == 1.0) return frameData;

    // 分析並找到最佳增益值以避免失真
    final optimalGain = _getOptimalGain(frameData, _audioGain);

    if (isDebug && optimalGain != _audioGain) {
      debugPrint(
          'Real-time gain adjusted from ${_audioGain.toStringAsFixed(2)} to ${optimalGain.toStringAsFixed(2)} to reduce distortion');
    }

    // 應用軟壓縮和優化後的增益
    return frameData.map((sample) => _softClip(sample, optimalGain)).toList();
  }

  /// Emit raw frame event when VAD processing is disabled
  void _emitRawFrameEvent(Float32List frameData) {
    // 計算分貝值和音量級別
    final double decibels = _calculateDecibels(frameData.toList());
    final int volumeLevel = _calculateVolumeLevel(decibels);

    // 發送原始音訊幀事件，但不進行 VAD 分析
    onVadEvent?.call(VadEvent(
      type: VadEventType.frameProcessed,
      timestamp: _getCurrentTimestamp(),
      message:
          'Raw frame processed (VAD disabled) at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
      probabilities: SpeechProbabilities(
          isSpeech: 0.0, // VAD 停用時設為 0
          notSpeech: 1.0, // VAD 停用時設為 1
          decibels: decibels,
          volumeLevel: volumeLevel),
      frameData: frameData.toList(),
    ));

    _currentSample += frameSamples;
  }

  /// Process a single frame of audio data.
  Future<void> _processFrame(Float32List data) async {
    if (_session == null) {
      debugPrint('VAD Iterator: Session not initialized.');
      return;
    }

    final (speechProb, modelOutputs) = await _runModelInference(data);

    // Create a copy of the frame data for the event
    final frameData = data.toList();

    // 計算分貝值
    final double decibels = _calculateDecibels(frameData);

    // 將分貝值映射到0-10的音量級別，並過濾過大或過小的聲音
    final int volumeLevel = _calculateVolumeLevel(decibels);

    // Emit the frame processed event
    onVadEvent?.call(VadEvent(
      type: VadEventType.frameProcessed,
      timestamp: _getCurrentTimestamp(),
      message:
          'Frame processed at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
      probabilities: SpeechProbabilities(
          isSpeech: speechProb,
          notSpeech: 1.0 - speechProb,
          decibels: decibels,
          volumeLevel: volumeLevel),
      frameData: frameData,
    ));

    for (var element in modelOutputs) {
      element?.release();
    }

    _currentSample += frameSamples;
    _handleStateTransitions(speechProb, data);
  }

  /// Run model inference based on the selected model version
  Future<(double, List<OrtValue?>)> _runModelInference(Float32List data) async {
    if (model == 'v5') {
      return _runV5ModelInference(data);
    } else {
      return _runLegacyModelInference(data);
    }
  }

  /// Run inference for Silero VAD v5 model
  Future<(double, List<OrtValue?>)> _runV5ModelInference(
      Float32List data) async {
    debugPrint('data.length=${data.length}, shape=[$_batch, $frameSamples]');
    debugPrint(
        '_state shape=[${_state.length}, ${_state[0].length}, ${_state[0][0].length}]');
    final inputOrt =
        OrtValueTensor.createTensorWithDataList(data, [_batch, frameSamples]);
    final srOrt = OrtValueTensor.createTensorWithData(sampleRate);

    // 確保 _state 是正確的維度：[2, 1, 128] 而不是 [2, 1, 128, 1]
    final flatState =
        _state.expand((layer) => layer.expand((batch) => batch)).toList();
    final stateOrt = OrtValueTensor.createTensorWithDataList(
        Float32List.fromList(flatState), [2, _batch, 128]);
    final runOptions = OrtRunOptions();

    final inputs = {'input': inputOrt, 'sr': srOrt, 'state': stateOrt};
    debugPrint('inputs.keys=${inputs.keys}');
    final outputs = _session!.run(runOptions, inputs);

    inputOrt.release();
    srOrt.release();
    stateOrt.release();
    runOptions.release();

    final speechProb = (outputs[0]?.value as List<List<double>>)[0][0];

    // 更新狀態，確保維度正確
    final newStateData = outputs[1]?.value as List<List<List<double>>>;
    _state = newStateData
        .map((layer) =>
            layer.map((batch) => Float32List.fromList(batch)).toList())
        .toList();

    return (speechProb, outputs);
  }

  /// Run inference for Silero VAD Legacy model
  Future<(double, List<OrtValue?>)> _runLegacyModelInference(
      Float32List data) async {
    final inputOrt =
        OrtValueTensor.createTensorWithDataList(data, [_batch, frameSamples]);
    final srOrt = OrtValueTensor.createTensorWithData(sampleRate);
    final hOrt = OrtValueTensor.createTensorWithDataList(_hide);
    final cOrt = OrtValueTensor.createTensorWithDataList(_cell);
    final runOptions = OrtRunOptions();

    final inputs = {'input': inputOrt, 'sr': srOrt, 'h': hOrt, 'c': cOrt};
    final outputs = _session!.run(runOptions, inputs);

    inputOrt.release();
    srOrt.release();
    hOrt.release();
    cOrt.release();
    runOptions.release();

    final speechProb = (outputs[0]?.value as List<List<double>>)[0][0];
    _hide = (outputs[1]?.value as List<List<List<double>>>)
        .map((e) => e.map((e) => Float32List.fromList(e)).toList())
        .toList();
    _cell = (outputs[2]?.value as List<List<List<double>>>)
        .map((e) => e.map((e) => Float32List.fromList(e)).toList())
        .toList();

    return (speechProb, outputs);
  }

  /// Handle state transitions based on speech probability
  void _handleStateTransitions(double speechProb, Float32List data) {
    if (speechProb >= positiveSpeechThreshold) {
      // Speech-positive frame
      if (!speaking) {
        speaking = true;
        onVadEvent?.call(VadEvent(
          type: VadEventType.start,
          timestamp: _getCurrentTimestamp(),
          message:
              'Speech started at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
        ));
        speechBuffer.addAll(preSpeechBuffer);
        preSpeechBuffer.clear();
      }
      redemptionCounter = 0;
      speechBuffer.add(data);
      speechPositiveFrameCount++;

      // Add validation event when speech frames exceed minimum threshold
      if (speechPositiveFrameCount == minSpeechFrames) {
        onVadEvent?.call(VadEvent(
          type: VadEventType.realStart,
          timestamp: _getCurrentTimestamp(),
          message:
              'Speech validated at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
        ));
      }
    } else if (speechProb < negativeSpeechThreshold) {
      // Handle speech-negative frame
      _handleSpeechNegativeFrame(data);
    } else {
      // Probability between thresholds
      _handleIntermediateFrame(data);
    }
  }

  /// Handle speech-negative frame
  void _handleSpeechNegativeFrame(Float32List data) {
    if (speaking) {
      if (++redemptionCounter >= redemptionFrames) {
        // End of speech
        speaking = false;
        redemptionCounter = 0;

        if (speechPositiveFrameCount >= minSpeechFrames) {
          // Valid speech segment
          onVadEvent?.call(VadEvent(
            type: VadEventType.end,
            timestamp: _getCurrentTimestamp(),
            message:
                'Speech ended at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
            audioData: _combineSpeechBuffer(),
          ));
        } else {
          // Misfire
          onVadEvent?.call(VadEvent(
            type: VadEventType.misfire,
            timestamp: _getCurrentTimestamp(),
            message:
                'Misfire detected at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
          ));
        }
        // Reset counters and buffers
        speechPositiveFrameCount = 0;
        speechBuffer.clear();
      } else {
        speechBuffer.add(data);
      }
    } else {
      // Not speaking, maintain pre-speech buffer
      _addToPreSpeechBuffer(data);
    }
  }

  /// Handle frame with probability between thresholds
  void _handleIntermediateFrame(Float32List data) {
    if (speaking) {
      speechBuffer.add(data);
      redemptionCounter = 0;
    } else {
      _addToPreSpeechBuffer(data);
    }
  }

  /// Forcefully end speech detection on pause/stop event.
  @override
  void forceEndSpeech() {
    if (speaking && speechPositiveFrameCount >= minSpeechFrames) {
      if (isDebug) debugPrint('VAD Iterator: Forcing speech end.');
      onVadEvent?.call(VadEvent(
        type: VadEventType.end,
        timestamp: _getCurrentTimestamp(),
        message:
            'Speech forcefully ended at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
        audioData: _combineSpeechBuffer(),
      ));
      // Reset state
      speaking = false;
      redemptionCounter = 0;
      speechPositiveFrameCount = 0;
      speechBuffer.clear();
      preSpeechBuffer.clear();
    }
  }

  /// 軟壓縮/軟限幅算法，比clamp更溫和，減少失真
  double _softClip(double sample, double gain) {
    // 應用增益
    double amplifiedSample = sample * gain;

    // 使用tanh函數進行軟壓縮，保留更多動態範圍
    // π/2是一個縮放因子，使結果更接近線性調整但避免硬截斷
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

  /// Manually end speech detection and return audio data
  @override
  Future<List<double>?> manualEndSpeech() async {
    if (isDebug) debugPrint('manualEndSpeech');
    try {
      if (speaking && speechPositiveFrameCount >= minSpeechFrames) {
        if (isDebug) debugPrint('VAD Iterator: Manually ending speech.');

        // Combine speech buffer
        final audioData = _combineSpeechBuffer();

        // Convert audio data to float list
        final buffer = audioData.buffer;
        final int16List = Int16List.view(buffer);

        // 先轉換回浮點數樣本
        final rawSamples = int16List.map((e) => e / 32768.0).toList();

        // 分析並求最佳增益值
        final optimalGain = _getOptimalGain(rawSamples, _audioGain);
        if (isDebug && optimalGain != _audioGain) {
          debugPrint(
              'Adjusted gain from ${_audioGain.toStringAsFixed(2)} to ${optimalGain.toStringAsFixed(2)} to reduce distortion');
        }

        // 應用軟壓縮和優化後的增益
        final floatSamples =
            rawSamples.map((e) => _softClip(e, optimalGain)).toList();

        // Emit event
        onVadEvent?.call(VadEvent(
          type: VadEventType.end,
          timestamp: _getCurrentTimestamp(),
          message:
              'Speech manually ended at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
          audioData: audioData,
        ));

        // Reset state
        speaking = false;
        redemptionCounter = 0;
        speechPositiveFrameCount = 0;
        speechBuffer.clear();
        preSpeechBuffer.clear();

        return floatSamples;
      }

      return null;
    } catch (e) {
      if (isDebug) debugPrint('Error in manualEndSpeech: $e');
      return null;
    }
  }

  void _addToPreSpeechBuffer(Float32List data) {
    preSpeechBuffer.add(data);
    while (preSpeechBuffer.length > preSpeechPadFrames) {
      preSpeechBuffer.removeAt(0);
    }
  }

  double _getCurrentTimestamp() {
    return _currentSample / sampleRate;
  }

  Uint8List _combineSpeechBuffer() {
    final int totalLength =
        speechBuffer.fold(0, (sum, frame) => sum + frame.length);
    final Float32List combined = Float32List(totalLength);
    int offset = 0;
    for (var frame in speechBuffer) {
      combined.setRange(offset, offset + frame.length, frame);
      offset += frame.length;
    }

    // 分析並找到最佳增益值
    final optimalGain = _getOptimalGain(combined, _audioGain);
    if (isDebug && optimalGain != _audioGain) {
      debugPrint(
          'Adjusted gain from ${_audioGain.toStringAsFixed(2)} to ${optimalGain.toStringAsFixed(2)} to reduce distortion');
    }

    // 應用軟壓縮和增益，然後轉換為Int16
    final int16Data = Int16List.fromList(combined.map((e) {
      // 應用軟壓縮代替簡單的clamp
      double processedSample = _softClip(e, optimalGain);

      // 確保值在-1.0到1.0範圍內（以防萬一）
      processedSample = processedSample.clamp(-1.0, 1.0);

      // 轉換為16位整數
      return (processedSample * 32767).toInt();
    }).toList());

    final Uint8List audioData = Uint8List.view(int16Data.buffer);
    return audioData;
  }

  List<double> _convertBytesToFloat32(Uint8List data) {
    final buffer = data.buffer;
    final int16List = Int16List.view(buffer);
    return int16List.map((e) => e / 32768.0).toList();
  }

  /// 計算音頻幀的分貝值
  double _calculateDecibels(List<double> audioFrame) {
    if (audioFrame.isEmpty) return 0.0;

    // 計算RMS (Root Mean Square)值
    double sumOfSquares = 0.0;
    for (var sample in audioFrame) {
      sumOfSquares += sample * sample;
    }
    final double rms = sqrt(sumOfSquares / audioFrame.length);

    // 防止對0取log
    if (rms <= 0.0) return 0.0;

    // 計算分貝值 (參考值為1.0，這是標準化音頻數據的最大值)
    // 標準公式：20 * log10(振幅/參考振幅)
    return 20.0 * log(rms) / ln10;
  }

  /// 將分貝值映射到0-10的音量級別並過濾噪音
  int _calculateVolumeLevel(double decibels) {
    // 設定閾值，過濾太大或太小的聲音
    // 典型的人聲大約在-60dB到0dB之間
    const double minDb = -60.0; // 最小有效分貝
    const double maxDb = -10.0; // 最大有效分貝

    // 如果低於最小閾值，視為背景噪音
    if (decibels < minDb) return 0;

    // 如果高於最大閾值，可能是噪音或太接近麥克風
    if (decibels > maxDb) return 10;

    // 將-60dB到-10dB的範圍映射到0-10級別
    final double normalizedDb = (decibels - minDb) / (maxDb - minDb);
    final int level = (normalizedDb * 10).round().clamp(0, 10);

    return level;
  }
}

/// Create VadHandlerNonWeb instance
VadIteratorBase createVadIterator({
  required bool isDebug,
  required int sampleRate,
  required int frameSamples,
  required double positiveSpeechThreshold,
  required double negativeSpeechThreshold,
  required int redemptionFrames,
  required int preSpeechPadFrames,
  required int minSpeechFrames,
  required bool submitUserSpeechOnPause,
  required String model,
  double audioGain = 1.0,
  bool realtimeGainEnabled = false,
}) {
  final iterator = VadIteratorNonWeb(
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

  // 設定即時增益
  iterator.setRealtimeGainEnabled(realtimeGainEnabled);

  return iterator;
}
