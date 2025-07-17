// vad_iterator_base.dart
import 'vad_event.dart';

/// Base class for Voice Activity Detection (VAD) iterator.
/// Only used for non-web platforms.
/// It is internally used by the [VadHandlerNonWeb] class.
/// But it can be used directly for more control over the VAD process. For example, to process non-streaming audio data.

abstract class VadIteratorBase {
  /// Audio gain to apply to output audio samples
  double get audioGain;

  /// Set audio gain value
  set audioGain(double value);

  /// Enable or disable real-time gain application (before VAD processing)
  void setRealtimeGainEnabled(bool enabled);

  /// Get current real-time gain status
  bool get isRealtimeGainEnabled;

  /// Enable or disable saving original audio (without gain applied)
  void setSaveOriginalAudio(bool enabled);

  /// Get current save original audio status
  bool get isSaveOriginalAudio;

  /// Enable or disable VAD processing while keeping audio stream active
  void setVadProcessingEnabled(bool enabled);

  /// Get current VAD processing status
  bool get isVadProcessingEnabled;

  /// Enable continuous recording mode (audio stream always active)
  void setContinuousRecordingMode(bool enabled);

  /// Get continuous recording mode status
  bool get isContinuousRecordingMode;

  /// Initialize the VAD model from the given [modelPath].
  Future<void> initModel(String modelPath);

  /// Reset the VAD iterator.
  void reset();

  /// Release the VAD iterator resources.
  void release();

  /// Set the VAD event callback.
  void setVadEventCallback(VadEventCallback callback);

  /// Process audio data.
  Future<void> processAudioData(List<int> data);

  /// Forcefully end speech detection on pause/stop event.
  void forceEndSpeech();

  /// Manually end speech detection and return audio data
  /// Similar to forceEndSpeech but returns the audio data
  /// Returns null if no speech was detected
  Future<List<double>?> manualEndSpeech();
}

/// Callback for VAD events.
typedef VadEventCallback = void Function(VadEvent event);
