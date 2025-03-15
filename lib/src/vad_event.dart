// vad_event.dart
import 'dart:typed_data';

/// VadEventType enum used by non-web VAD handler
enum VadEventType {
  /// Speech start event
  start,

  /// Speech end event
  end,

  /// Speech volume change event
  voiceChange,

  /// VAD misfire event
  misfire,

  /// Error event
  error,

  /// Audio frame event
  audioFrame
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
  final Uint8List? audioData;

  /// Voice volume level (in dB)
  final double? volumeLevel;

  /// Constructor
  VadEvent({
    required this.type,
    required this.timestamp,
    required this.message,
    this.audioData,
    this.volumeLevel,
  });
}
