// vad_handler_web.dart

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
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
  final StreamController<double> _onVoiceChangeController =
      StreamController<double>.broadcast();

  /// Whether to print debug messages
  bool isDebug = false;

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
  Stream<double> get onVoiceChange => _onVoiceChangeController.stream;

  @override
  void startListening(
      {double positiveSpeechThreshold = 0.5,
      double negativeSpeechThreshold = 0.35,
      int preSpeechPadFrames = 1,
      int redemptionFrames = 8,
      int frameSamples = 1536,
      int minSpeechFrames = 3,
      bool submitUserSpeechOnPause = false}) {
    if (isDebug) {
      debugPrint(
          'VadHandlerWeb: startListening: Calling startListeningImpl with parameters: '
          'positiveSpeechThreshold: $positiveSpeechThreshold, '
          'negativeSpeechThreshold: $negativeSpeechThreshold, '
          'preSpeechPadFrames: $preSpeechPadFrames, '
          'redemptionFrames: $redemptionFrames, '
          'frameSamples: $frameSamples, '
          'minSpeechFrames: $minSpeechFrames, '
          'submitUserSpeechOnPause: $submitUserSpeechOnPause');
    }
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
          break;
        case 'onSpeechStart':
          if (isDebug) {
            debugPrint('VadHandlerWeb: onSpeechStart');
          }
          _onSpeechStartController.add(null);
          break;
        case 'onVADMisfire':
          if (isDebug) {
            debugPrint('VadHandlerWeb: onVADMisfire');
          }
          _onVADMisfireController.add(null);
          break;
        case 'onVoiceChange':
          if (eventData.containsKey('volume')) {
            final double amplitude = (eventData['volume'] as num).toDouble();
            // Convert volume to 16-bit PCM range (-32768 to 32767)
            double normalizedAmplitude = amplitude * 32768.0;

            // Calculate decibels (same as non-web version)
            double db = 20 * (log(normalizedAmplitude.abs() / 32768.0) / ln10);

            // Normalize dB value to 0-1 range
            double minDb = -90.0; // Minimum dB value
            double maxDb = 0.0; // Maximum dB value
            double normalizedDb =
                ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);

            if (isDebug) {
              debugPrint(
                  'VadHandlerWeb: Raw Amplitude: $amplitude, PCM: $normalizedAmplitude, dB: $db, normalized: $normalizedDb');
            }
            _onVoiceChangeController.add(normalizedDb);
          }
          break;
        default:
          debugPrint("Unknown event: $eventType");
      }
    } catch (e, st) {
      debugPrint('Error handling event: $e');
      debugPrint('Stack Trace: $st');
    }
  }

  @override
  void dispose() {
    if (isDebug) {
      debugPrint('VadHandlerWeb: dispose');
    }
    _onSpeechEndController.close();
    _onSpeechStartController.close();
    _onVADMisfireController.close();
    _onErrorController.close();
    _onVoiceChangeController.close();
  }

  @override
  void stopListening() {
    if (isDebug) {
      debugPrint('VadHandlerWeb: stopListening');
    }
    stopListeningImpl();
  }
}

/// Create a VAD handler for the web
/// isDebug is used to print debug messages
/// modelPath is not used in the web implementation, adding it will not have any effect
VadHandlerBase createVadHandler({required isDebug, modelPath}) =>
    VadHandlerWeb(isDebug: isDebug);
