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
    _audioPlayer.onDurationChanged.listen((Duration duration) {});

    _audioPlayer.onPositionChanged.listen((Duration position) {});

    _audioPlayer.onPlayerComplete.listen((_) {
      setState(() {
        _isPlaying = false;
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

  Widget _buildRecordingCard(Recording recording, int index) {
    Color cardColor;
    IconData icon;
    String title;
    bool canPlay = false;

    switch (recording.type) {
      case RecordingType.speechStart:
        cardColor = Colors.blue.withOpacity(0.2);
        icon = Icons.mic;
        title = '語音檢測開始';
        break;
      case RecordingType.realSpeechStart:
        cardColor = Colors.green.withOpacity(0.2);
        icon = Icons.mic;
        title = '確認為真實語音';
        break;
      case RecordingType.speechEnd:
        cardColor = Colors.purple.withOpacity(0.2);
        icon = Icons.stop_circle;
        title = '語音檢測結束';
        canPlay = recording.samples != null && recording.samples!.isNotEmpty;
        break;
      case RecordingType.misfire:
        cardColor = Colors.orange.withOpacity(0.2);
        icon = Icons.error_outline;
        title = 'VAD誤觸發';
        break;
      case RecordingType.error:
        cardColor = Colors.red.withOpacity(0.2);
        icon = Icons.error;
        title = '錯誤';
        break;
      case RecordingType.manualStop:
        cardColor = Colors.teal.withOpacity(0.2);
        icon = Icons.stop;
        title = '手動停止語音';
        canPlay = recording.samples != null && recording.samples!.isNotEmpty;
        break;
      case RecordingType.silenceThresholdReached:
        cardColor = Colors.amber.withOpacity(0.2);
        icon = Icons.volume_off;
        title = '已達靜音閾值';
        break;
    }

    return Card(
      color: cardColor,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 28, color: Colors.white),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          '${recording.timestamp.hour.toString().padLeft(2, '0')}:${recording.timestamp.minute.toString().padLeft(2, '0')}:${recording.timestamp.second.toString().padLeft(2, '0')}',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
        trailing: canPlay
            ? Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: Icon(
                    _isPlaying && _currentlyPlayingIndex == index
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    _playRecording(recording, index);
                  },
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VAD Demo'),
        centerTitle: true,
        elevation: 4,
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
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed:
                          widget.isListening ? null : widget.onStartListening,
                      icon: const Icon(Icons.mic),
                      label: const Text('開始'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
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
                      label: Text(widget.isSpeechDetected ? '儲存並停止' : '停止'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            widget.isSpeechDetected ? Colors.blue : Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: widget.onRequestMicrophonePermission,
                  icon: const Icon(Icons.settings_voice),
                  label: const Text('請求麥克風權限'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // 添加音量指示器
                if (widget.isListening) ...[
                  const SizedBox(height: 24),
                  VolumeIndicatorWithLabel(
                    volumeLevel: widget.volumeLevel / 10,
                    decibels: widget.decibels,
                    width: MediaQuery.of(context).size.width - 32,
                  ),
                ],
              ],
            ),
          ),

          // Recording list
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                itemCount: widget.recordings.length,
                itemBuilder: (context, index) {
                  return _buildRecordingCard(widget.recordings[index], index);
                },
              ),
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
