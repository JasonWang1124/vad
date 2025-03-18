// lib/ui/vad_ui.dart

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart' as audioplayers;
import 'package:vad_example/recording.dart';
import 'package:vad_example/audio_utils.dart';
import 'package:vad_example/vad_settings_dialog.dart';
import 'package:vad_example/ui/volume_indicator.dart';

class VadUIController {
  Function? scrollToBottom;

  void dispose() {
    scrollToBottom = null;
  }
}

class VadUI extends StatefulWidget {
  final List<Recording> recordings;
  final bool isListening;
  final bool isSpeechDetected;
  final int volumeLevel;
  final double decibels;
  final VadSettings settings;
  final Function() onStartListening;
  final Function() onStopListening;
  final Function() onManualStopWithAudio;
  final Function() onRequestMicrophonePermission;
  final Function() onShowSettingsDialog;
  final VadUIController? controller;

  const VadUI({
    super.key,
    required this.recordings,
    required this.isListening,
    required this.isSpeechDetected,
    required this.volumeLevel,
    required this.decibels,
    required this.settings,
    required this.onStartListening,
    required this.onStopListening,
    required this.onManualStopWithAudio,
    required this.onRequestMicrophonePermission,
    required this.onShowSettingsDialog,
    this.controller,
  });

  @override
  State<VadUI> createState() => _VadUIState();
}

class _VadUIState extends State<VadUI> {
  final audioplayers.AudioPlayer _audioPlayer = audioplayers.AudioPlayer();
  final ScrollController _scrollController = ScrollController();

  // Audio player state
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  int? _currentlyPlayingIndex;

  @override
  void initState() {
    super.initState();
    _initializeAudioPlayer();
    _setupAudioPlayerListeners();
    if (widget.controller != null) {
      widget.controller!.scrollToBottom = _scrollToBottom;
    }
  }

  Future<void> _initializeAudioPlayer() async {
    await _audioPlayer.setAudioContext(
      audioplayers.AudioContext(
        iOS: audioplayers.AudioContextIOS(
          options: const {audioplayers.AVAudioSessionOptions.mixWithOthers},
          category: audioplayers.AVAudioSessionCategory.playAndRecord,
        ),
        android: const audioplayers.AudioContextAndroid(
          contentType: audioplayers.AndroidContentType.speech,
          usageType: audioplayers.AndroidUsageType.voiceCommunication,
        ),
      ),
    );
  }

  void _setupAudioPlayerListeners() {
    _audioPlayer.onDurationChanged.listen((Duration duration) {
      setState(() => _duration = duration);
    });

    _audioPlayer.onPositionChanged.listen((Duration position) {
      setState(() => _position = position);
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
        _currentlyPlayingIndex = null;
      });
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlaying = state == audioplayers.PlayerState.playing;
      });
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _playRecording(Recording recording, int index) async {
    if (recording.type == RecordingType.misfire) return;

    try {
      if (_currentlyPlayingIndex == index && _isPlaying) {
        await _audioPlayer.pause();
        setState(() {
          _isPlaying = false;
        });
      } else {
        if (_currentlyPlayingIndex != index) {
          String uri = AudioUtils.createWavUrl(recording.samples!);
          await _audioPlayer.play(audioplayers.UrlSource(uri));
          setState(() {
            _currentlyPlayingIndex = index;
            _isPlaying = true;
          });
        } else {
          await _audioPlayer.resume();
          setState(() {
            _isPlaying = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  Future<void> _seekTo(Duration position) async {
    await _audioPlayer.seek(position);
    setState(() {
      _position = position;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  Widget _buildRecordingItem(Recording recording, int index) {
    final bool isCurrentlyPlaying = _currentlyPlayingIndex == index;
    final bool hasAudio = (recording.type == RecordingType.speechEnd ||
            recording.type == RecordingType.manualStop) &&
        recording.samples != null;

    // Icon and color based on recording type
    IconData typeIcon;
    Color iconColor;
    Color backgroundColor;
    String typeTitle;

    switch (recording.type) {
      case RecordingType.speechStart:
        typeIcon = Icons.mic;
        iconColor = Colors.white;
        backgroundColor = Colors.orange;
        typeTitle = 'Speech Detected';
        break;
      case RecordingType.realSpeechStart:
        typeIcon = Icons.record_voice_over;
        iconColor = Colors.white;
        backgroundColor = Colors.green;
        typeTitle = 'Real Speech Started';
        break;
      case RecordingType.speechEnd:
        typeIcon =
            isCurrentlyPlaying && _isPlaying ? Icons.pause : Icons.play_arrow;
        iconColor = Colors.blue[100]!;
        backgroundColor = Colors.blue[900]!;
        typeTitle = 'Recorded Speech';
        break;
      case RecordingType.manualStop:
        typeIcon =
            isCurrentlyPlaying && _isPlaying ? Icons.pause : Icons.play_arrow;
        iconColor = Colors.blue[100]!;
        backgroundColor = Colors.purple;
        typeTitle = 'Manually Stopped Speech';
        break;
      case RecordingType.misfire:
        typeIcon = Icons.warning_amber_rounded;
        iconColor = Colors.white;
        backgroundColor = Colors.red;
        typeTitle = 'VAD Misfire';
        break;
      case RecordingType.error:
        typeIcon = Icons.error_outline;
        iconColor = Colors.white;
        backgroundColor = Colors.deepPurple;
        typeTitle = 'Error Event';
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: backgroundColor,
              child: Icon(typeIcon, color: iconColor),
            ),
            title: Text(
              '$typeTitle ${index + 1}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: recording.type == RecordingType.error ||
                        recording.type == RecordingType.misfire
                    ? Colors.red[300]
                    : null,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatTimestamp(recording.timestamp)),
                if (hasAudio)
                  Text(
                    '${(recording.samples!.length / 16000).toStringAsFixed(1)} seconds',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
              ],
            ),
            onTap: hasAudio ? () => _playRecording(recording, index) : null,
          ),
          if (isCurrentlyPlaying && hasAudio) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _position.inMilliseconds.toDouble(),
                      min: 0,
                      max: _duration.inMilliseconds.toDouble() + 1,
                      onChanged: (value) {
                        _seekTo(Duration(milliseconds: value.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_position)),
                        Text(_formatDuration(_duration)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VAD Demo'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: widget.onShowSettingsDialog,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          // Controls
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed:
                          widget.isListening ? null : widget.onStartListening,
                      icon: const Icon(Icons.mic),
                      label: const Text('Start'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: widget.isListening
                          ? (widget.isSpeechDetected
                              ? widget.onManualStopWithAudio
                              : widget.onStopListening)
                          : null,
                      icon: Icon(
                          widget.isSpeechDetected ? Icons.save : Icons.stop),
                      label: Text(
                          widget.isSpeechDetected ? 'Save & Stop' : 'Stop'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            widget.isSpeechDetected ? Colors.blue : Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: widget.onRequestMicrophonePermission,
                  icon: const Icon(Icons.settings_voice),
                  label: const Text('Request Mic Permission'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),

                // 添加音量指示器
                if (widget.isListening) ...[
                  const SizedBox(height: 16),
                  VolumeIndicatorWithLabel(
                    volumeLevel: widget.volumeLevel,
                    decibels: widget.decibels,
                    width: MediaQuery.of(context).size.width - 32,
                  ),
                ],
              ],
            ),
          ),

          // Recording list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              itemCount: widget.recordings.length,
              itemBuilder: (context, index) {
                return _buildRecordingItem(widget.recordings[index], index);
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _scrollController.dispose();
    if (widget.controller != null) {
      widget.controller!.dispose();
    }
    super.dispose();
  }
}
