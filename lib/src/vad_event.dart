// vad_event.dart
import 'dart:typed_data';

/// VadEventType enum used by non-web VAD handler
enum VadEventType {
  /// Speech start event
  start,

  /// Real speech start event
  realStart,

  /// Speech end event
  end,

  /// Frame processed event
  frameProcessed,

  /// VAD misfire event
  misfire,

  /// Error event
  error,
}

/// VadProbabilities class
class SpeechProbabilities {
  /// Probability of speech
  final double isSpeech;

  /// Probability of not speech
  final double notSpeech;

  /// Decibel value of the audio frame
  final double decibels;

  /// Volume level (0-10) of the audio frame
  final int volumeLevel;

  /// Constructor
  SpeechProbabilities({
    required this.isSpeech,
    required this.notSpeech,
    required this.decibels,
    required this.volumeLevel,
  });
}

/// VadEvent class
class VadEvent {
  /// VadEventType
  final VadEventType type;

  /// Timestamp
  final double timestamp;

  /// Message
  final String message;

  /// Audio data
  /// Note: For VadEventType.end, the audio data is returned with original gain (1.0).
  /// The audio gain is applied when converting to float samples in manualEndSpeech and _handleVadEvent.
  final Uint8List? audioData;

  /// Speech probabilities
  final SpeechProbabilities? probabilities;

  /// Frame data
  final List<double>? frameData;

  /// Constructor
  VadEvent({
    required this.type,
    required this.timestamp,
    required this.message,
    this.probabilities,
    this.audioData,
    this.frameData,
  });
}
