// vad_handler_base.dart

import 'dart:async';

/// Abstract class for VAD handler
abstract class VadHandlerBase {
  /// Stream of speech end events
  Stream<List<double>> get onSpeechEnd;

  /// Stream of speech start events
  Stream<void> get onSpeechStart;

  /// Stream of VAD misfire events
  Stream<void> get onVADMisfire;

  /// Stream of error events
  Stream<String> get onError;

  /// Stream of voice volume changes (in dB)
  Stream<double> get onVoiceChange;

  /// Start listening for speech events
  void startListening(
      {double positiveSpeechThreshold = 0.5,
      double negativeSpeechThreshold = 0.35,
      int preSpeechPadFrames = 1,
      int redemptionFrames = 8,
      int frameSamples = 1536,
      int minSpeechFrames = 3,
      bool submitUserSpeechOnPause = false});

  /// Stop listening for speech events
  void stopListening();

  /// Dispose the VAD handler
  void dispose();
}
