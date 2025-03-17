import 'dart:typed_data';
import 'dart:math' as math;

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
  double positiveSpeechThreshold = 0.3;

  /// Threshold for negative speech detection.
  double negativeSpeechThreshold = 0.2;

  /// Number of frames for redemption after speech detection.
  int redemptionFrames = 12;

  /// Number of samples in a frame.
  /// Default is 1536 samples for 96ms at 16kHz sample rate.
  /// * > WARNING! Silero VAD models were trained using 512, 1024, 1536 samples for 16000 sample rate and 256, 512, 768 samples for 8000 sample rate.
  /// * > Values other than these may affect model perfomance!!
  /// * In this context, audio fed to the VAD model always has sample rate 16000. It is probably a good idea to leave this at 1536.
  int frameSamples = 1536;

  /// Number of frames to pad before speech detection.
  int preSpeechPadFrames = 2;

  /// Minimum number of speech frames to consider as valid speech.
  int minSpeechFrames = 2;

  /// Sample rate of the audio data.
  int sampleRate = 16000;

  /// Flag to submit user speech on pause/stop event.
  bool submitUserSpeechOnPause = false;

  // Internal variables
  /// Flag to indicate speech detection state.
  bool speaking = false;

  /// Counter for speech redemption frames.
  int redemptionCounter = 0;

  /// Counter for positive speech frames.
  int speechPositiveFrameCount = 0;
  int _currentSample = 0; // To track position in samples

  /// Number of frames to ignore at startup to prevent false detections.
  int _warmupFrames = 10; // 默認忽略前10幀

  /// Counter for processed frames.
  int _processedFrames = 0;

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
  }) : frameByteCount = frameSamples * 2;

  /// Initialize the VAD model from the given [modelPath].
  @override
  Future<void> initModel(String modelPath) async {
    try {
      _sessionOptions = OrtSessionOptions()
        ..setInterOpNumThreads(1)
        ..setIntraOpNumThreads(1)
        ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
      final rawAssetFile = await rootBundle.load(modelPath);
      final bytes = rawAssetFile.buffer.asUint8List();
      _session = OrtSession.fromBuffer(bytes, _sessionOptions!);
      if (isDebug) debugPrint('VAD model initialized from $modelPath.');
    } catch (e) {
      debugPrint('VAD model initialization failed: $e');
      onVadEvent?.call(VadEvent(
        type: VadEventType.error,
        timestamp: _getCurrentTimestamp(),
        message: 'VAD model initialization failed: $e',
      ));
    }
  }

  /// Reset the VAD iterator.
  @override
  void reset() {
    speaking = false;
    redemptionCounter = 0;
    speechPositiveFrameCount = 0;
    _currentSample = 0;
    _processedFrames = 0; // 重置已處理幀計數器
    preSpeechBuffer.clear();
    speechBuffer.clear();
    _byteBuffer.clear();
    _hide = List.filled(
        2, List.filled(_batch, Float32List.fromList(List.filled(64, 0.0))));
    _cell = List.filled(
        2, List.filled(_batch, Float32List.fromList(List.filled(64, 0.0))));
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
    if (data.isEmpty) {
      if (isDebug) debugPrint('VAD Iterator: Empty audio data received.');
      return;
    }

    // 將音訊數據轉換為 Int16List 用於計算音量
    final int16List = Uint8List.fromList(data).buffer.asInt16List();

    // 計算音量級別 (RMS 轉換為分貝)
    double sum = 0;
    for (int i = 0; i < int16List.length; i++) {
      sum += int16List[i] * int16List[i];
    }
    final double rms = sum > 0 ? math.sqrt(sum / int16List.length) : 0;
    final double normalizedRms = rms / 32768.0; // 正規化到 0-1 範圍

    // 計算分貝值 (避免對數運算出現問題)
    double db;
    if (normalizedRms < 0.0001) {
      // 非常小的聲音
      db = -60.0; // 靜音
    } else {
      db = 20 * math.log(normalizedRms) / math.ln10;
    }

    // 確保分貝值在合理範圍內
    db = db.clamp(-60.0, 0.0);

    // 發送音訊幀事件，包含音量級別
    onVadEvent?.call(VadEvent(
      type: VadEventType.audioFrame,
      timestamp: _getCurrentTimestamp(),
      message: 'Audio frame at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
      audioData: Uint8List.fromList(data),
      volumeLevel: db,
    ));

    // 將音訊數據轉換為 Float32List
    final Float32List floatSamples = Float32List(int16List.length);
    for (int i = 0; i < int16List.length; i++) {
      floatSamples[i] = int16List[i] / 32768.0;
    }

    // 處理音訊數據
    _byteBuffer.addAll(data);

    while (_byteBuffer.length >= frameByteCount) {
      final frameBytes = _byteBuffer.sublist(0, frameByteCount);
      _byteBuffer.removeRange(0, frameByteCount);
      final frameData = _convertBytesToFloat32(Uint8List.fromList(frameBytes));
      await _processFrame(Float32List.fromList(frameData));
    }
  }

  /// Process a single frame of audio data.
  Future<void> _processFrame(Float32List data) async {
    if (_session == null) {
      debugPrint('VAD Iterator: Session not initialized.');
      return;
    }

    // 增加已處理幀計數
    _processedFrames++;

    // 如果在預熱階段，則忽略此幀
    if (_processedFrames <= _warmupFrames) {
      if (isDebug) {
        debugPrint(
            'VAD Iterator: Warming up, ignoring frame $_processedFrames of $_warmupFrames');
      }
      _addToPreSpeechBuffer(data);
      return;
    }

    // Run model inference
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

    // Output probability & update h,c recursively
    final speechProb = (outputs[0]?.value as List<List<double>>)[0][0];
    _hide = (outputs[1]?.value as List<List<List<double>>>)
        .map((e) => e.map((e) => Float32List.fromList(e)).toList())
        .toList();
    _cell = (outputs[2]?.value as List<List<List<double>>>)
        .map((e) => e.map((e) => Float32List.fromList(e)).toList())
        .toList();
    for (var element in outputs) {
      element?.release();
    }

    _currentSample += frameSamples;

    // Handle state transitions
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
    } else if (speechProb < negativeSpeechThreshold) {
      // Speech-negative frame
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
    } else {
      // Probability between thresholds, ignore frame for state transitions
      if (speaking) {
        speechBuffer.add(data);
        redemptionCounter = 0;
      } else {
        _addToPreSpeechBuffer(data);
      }
    }
  }

  /// Forcefully end speech detection on pause/stop event.
  @override
  void forceEndSpeech() {
    if (!speaking) return;

    if (isDebug) debugPrint('VAD Iterator: Forcing speech end.');

    // Generate end event
    onVadEvent?.call(VadEvent(
      type: VadEventType.end,
      timestamp: _getCurrentTimestamp(),
      message:
          'Speech forcefully ended at ${_getCurrentTimestamp().toStringAsFixed(3)}s',
      audioData: _combineSpeechBuffer(),
      volumeLevel: null,
    ));

    // Reset state
    speaking = false;
    redemptionCounter = 0;
    speechPositiveFrameCount = 0;
    speechBuffer.clear();
    preSpeechBuffer.clear();
  }

  @override
  bool isSpeaking() {
    return speaking;
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
    final int16Data = Int16List.fromList(
        combined.map((e) => (e * 32767).clamp(-32768, 32767).toInt()).toList());
    final Uint8List audioData = Uint8List.view(int16Data.buffer);
    return audioData;
  }

  List<double> _convertBytesToFloat32(Uint8List data) {
    final buffer = data.buffer;
    final int16List = Int16List.view(buffer);
    return int16List.map((e) => e / 32768.0).toList();
  }

  @override
  void setWarmupFrames(int frames) {
    _warmupFrames = frames;
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
}) {
  return VadIteratorNonWeb(
    isDebug: isDebug,
    sampleRate: sampleRate,
    frameSamples: frameSamples,
    positiveSpeechThreshold: positiveSpeechThreshold,
    negativeSpeechThreshold: negativeSpeechThreshold,
    redemptionFrames: redemptionFrames,
    preSpeechPadFrames: preSpeechPadFrames,
    minSpeechFrames: minSpeechFrames,
    submitUserSpeechOnPause: submitUserSpeechOnPause,
  );
}
