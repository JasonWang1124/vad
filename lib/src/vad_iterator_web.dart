import 'package:vad/src/vad_iterator_base.dart';

/// VadIteratorWeb class
/// DO NOT USE
/// Not implemented for web, since Web uses JavaScript library for VAD
/// Only added for compatibility with non-web platforms
class VadIteratorWeb implements VadIteratorBase {
  double _audioGain = 1.0;
  bool _realtimeGainEnabled = false;

  @override
  double get audioGain => _audioGain;

  @override
  set audioGain(double value) {
    _audioGain = value;
  }

  @override
  void setRealtimeGainEnabled(bool enabled) {
    _realtimeGainEnabled = enabled;
    // Web 版本不支援即時增益，僅保存狀態以保持相容性
  }

  @override
  bool get isRealtimeGainEnabled => _realtimeGainEnabled;

  @override
  void setVadProcessingEnabled(bool enabled) {
    // Web 版本不支援條件式 VAD 處理，僅保存狀態以保持相容性
  }

  @override
  bool get isVadProcessingEnabled => true;

  @override
  void setContinuousRecordingMode(bool enabled) {
    // Web 版本不支援持續錄音模式，僅保存狀態以保持相容性
  }

  @override
  bool get isContinuousRecordingMode => false;

  @override
  void forceEndSpeech() {
    throw UnimplementedError();
  }

  @override
  Future<List<double>?> manualEndSpeech() {
    throw UnimplementedError();
  }

  @override
  Future<void> initModel(String modelPath) {
    throw UnimplementedError();
  }

  @override
  Future<void> processAudioData(List<int> data) {
    throw UnimplementedError();
  }

  @override
  void release() {
    throw UnimplementedError();
  }

  @override
  void reset() {
    throw UnimplementedError();
  }

  @override
  void setVadEventCallback(VadEventCallback callback) {
    throw UnimplementedError();
  }
}

/// Create VadHandlerNonWeb instance
VadIteratorBase createVadIterator(
    {required bool isDebug,
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
    bool realtimeGainEnabled = false}) {
  final iterator = VadIteratorWeb();
  iterator.audioGain = audioGain;
  iterator.setRealtimeGainEnabled(realtimeGainEnabled);
  return iterator;
}
