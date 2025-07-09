// lib/ui/vad_ui.dart

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vad_example/recording.dart';
import 'package:vad_example/audio_utils.dart';
import 'package:vad_example/vad_settings_dialog.dart';
import 'package:vad_example/ui/volume_indicator.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

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

  // 新增持續錄音模式控制回調
  final Function()? onEnableContinuousRecording;
  final Function()? onQuickStartVad;
  final Function()? onQuickStopVad;
  final Function()? onDisableContinuousRecording;
  final bool? isContinuousRecordingMode;
  final bool? isVadProcessingEnabled;

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
    this.onEnableContinuousRecording,
    this.onQuickStartVad,
    this.onQuickStopVad,
    this.onDisableContinuousRecording,
    this.isContinuousRecordingMode,
    this.isVadProcessingEnabled,
  });

  @override
  State<VadUI> createState() => _VadUIState();
}

class _VadUIState extends State<VadUI> {
  final AudioPlayer _audioPlayer = AudioPlayer();
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
      AudioContext(
        iOS: AudioContextIOS(
          options: const {AVAudioSessionOptions.mixWithOthers},
          category: AVAudioSessionCategory.playAndRecord,
        ),
        android: const AudioContextAndroid(
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.voiceCommunication,
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
        _isPlaying = state == PlayerState.playing;
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
          await _audioPlayer.play(UrlSource(uri));
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

  Future<void> _saveRecording(Recording recording) async {
    if (recording.samples == null || recording.samples!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法儲存：音檔為空')),
      );
      return;
    }

    try {
      // 檢查權限
      if (Platform.isAndroid || Platform.isIOS) {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
          if (!status.isGranted) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('需要儲存權限才能保存錄音')),
            );
            return;
          }
        }
      }

      // 創建檔案名稱，使用時間戳
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'vad_recording_$timestamp.wav';

      // 設定檔案路徑
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';

      // 將音訊樣本轉換為WAV格式
      final wavData = AudioUtils.float32ToWav(recording.samples!);

      // 寫入檔案
      final file = File(filePath);
      await file.writeAsBytes(wavData);

      // 顯示成功訊息
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('錄音已儲存至: $filePath'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('儲存失敗: $e')),
      );
    }
  }

  Widget _buildRecordingCard(Recording recording, int index) {
    Color cardColor;
    IconData icon;
    String title;
    bool canPlay = false;

    switch (recording.type) {
      case RecordingType.speechStart:
        cardColor = Colors.blue.withValues(alpha: 0.2);
        icon = Icons.mic;
        title = '語音檢測開始';
        break;
      case RecordingType.realSpeechStart:
        cardColor = Colors.green.withValues(alpha: 0.2);
        icon = Icons.mic;
        title = '確認為真實語音';
        break;
      case RecordingType.speechEnd:
        cardColor = Colors.purple.withValues(alpha: 0.2);
        icon = Icons.stop_circle;
        title = '語音檢測結束';
        canPlay = recording.samples != null && recording.samples!.isNotEmpty;
        break;
      case RecordingType.misfire:
        cardColor = Colors.orange.withValues(alpha: 0.2);
        icon = Icons.error_outline;
        title = 'VAD誤觸發';
        break;
      case RecordingType.error:
        cardColor = Colors.red.withValues(alpha: 0.2);
        icon = Icons.error;
        title = '錯誤';
        break;
      case RecordingType.manualStop:
        cardColor = Colors.teal.withValues(alpha: 0.2);
        icon = Icons.stop;
        title = '手動停止語音';
        canPlay = recording.samples != null && recording.samples!.isNotEmpty;
        break;
      case RecordingType.silenceThresholdReached:
        cardColor = Colors.amber.withValues(alpha: 0.2);
        icon = Icons.volume_off;
        title = '已達靜音閾值';
        break;
    }

    // 針對含有音頻樣本的錄音項目，添加儲存按鈕
    List<Widget> actions = [];

    if (canPlay) {
      actions.add(
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
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
        ),
      );

      // 新增儲存按鈕
      actions.add(
        Container(
          margin: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            icon: const Icon(
              Icons.save_alt,
              color: Colors.white,
            ),
            onPressed: () {
              _saveRecording(recording);
            },
            tooltip: '另存新檔',
          ),
        ),
      );
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
            color: Colors.white.withValues(alpha: 0.1),
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
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        trailing: actions.isEmpty
            ? null
            : (actions.length == 1
                ? actions.first
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions,
                  )),
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
                  color: Colors.black.withValues(alpha: 0.1),
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

                // 持續錄音模式控制區域
                if (widget.onEnableContinuousRecording != null) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  Text(
                    '持續錄音模式 (幾乎 0 冷啟動)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),

                  Text(
                    '音訊流保持活躍，VAD 處理可快速開關',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 16),

                  // 持續錄音模式狀態顯示
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (widget.isContinuousRecordingMode ?? false)
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (widget.isContinuousRecordingMode ?? false)
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          (widget.isContinuousRecordingMode ?? false)
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: (widget.isContinuousRecordingMode ?? false)
                              ? Colors.green
                              : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '持續錄音: ${(widget.isContinuousRecordingMode ?? false) ? "已啟用" : "已停用"}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'VAD 處理: ${(widget.isVadProcessingEnabled ?? true) ? "已啟用" : "已停用"}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 持續錄音模式控制按鈕
                  if (!(widget.isContinuousRecordingMode ?? false)) ...[
                    // 啟用持續錄音模式
                    ElevatedButton.icon(
                      onPressed: widget.onEnableContinuousRecording,
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text('啟用持續錄音模式'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ] else ...[
                    // 持續錄音模式已啟用時的控制按鈕
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (widget.isVadProcessingEnabled ?? true)
                                ? widget.onQuickStopVad
                                : widget.onQuickStartVad,
                            icon: Icon((widget.isVadProcessingEnabled ?? true)
                                ? Icons.pause
                                : Icons.play_arrow),
                            label: Text((widget.isVadProcessingEnabled ?? true)
                                ? '快速停止'
                                : '快速啟動'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  (widget.isVadProcessingEnabled ?? true)
                                      ? Colors.orange
                                      : Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: widget.onDisableContinuousRecording,
                            icon: const Icon(Icons.stop),
                            label: const Text('停用模式'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],

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
