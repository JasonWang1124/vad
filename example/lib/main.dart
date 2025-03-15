// main.dart

import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart' as audioplayers;
import 'package:vad/vad.dart';
import 'audio_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VAD Example',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        sliderTheme: SliderThemeData(
          activeTrackColor: Colors.blue[400],
          inactiveTrackColor: Colors.grey[800],
          thumbColor: Colors.blue[300],
          overlayColor: Colors.blue.withAlpha(32),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[700],
            foregroundColor: Colors.white,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.blue[300],
          ),
        ),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum RecordingType {
  speech,
  misfire,
}

class Recording {
  final List<double>? samples;
  final RecordingType type;
  final DateTime timestamp;

  Recording({
    this.samples,
    required this.type,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Recording> recordings = [];
  audioplayers.AudioPlayer? _audioPlayer;
  late final dynamic _vadHandler;
  bool isListening = false;
  int frameSamples = 1536; // 1 frame = 1536 samples = 96ms
  int minSpeechFrames = 3;
  int preSpeechPadFrames = 10;
  int redemptionFrames = 8;
  bool submitUserSpeechOnPause = true;
  bool isWindowsPlatform = false;

  // Audio player state
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  int? _currentlyPlayingIndex;
  double currentDecibel = -60.0; // 新增分貝值狀態

  // 新增音訊幀緩衝區
  final List<Uint8List> _audioFrameBuffer = [];
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _initializeAudioPlayer();
    _setupAudioPlayerListeners();
    _initializePlatformSpecifics();
  }

  void _initializePlatformSpecifics() {
    try {
      isWindowsPlatform = Platform.isWindows;

      // 在所有平台上都初始化 VAD
      _vadHandler = VadHandler.create(isDebug: true);
      _setupVadHandler();

      if (isWindowsPlatform) {
        debugPrint('Windows 平台檢測到，權限請求可能不支援');
      }
    } catch (e) {
      debugPrint('平台檢測錯誤: $e');
      // 假設是 Web 平台或其他不支援 dart:io 的平台
      _vadHandler = VadHandler.create(isDebug: true);
      _setupVadHandler();
    }
  }

  void _setupAudioPlayerListeners() {
    // 在某些平台上可能不支援某些功能，所以我們使用 try-catch 來處理
    try {
      _audioPlayer?.onDurationChanged.listen((Duration duration) {
        if (!mounted) return;
        setState(() => _duration = duration);
      });

      _audioPlayer?.onPositionChanged.listen((Duration position) {
        if (!mounted) return;
        setState(() => _position = position);
      });

      _audioPlayer?.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        setState(() {
          _isPlaying = state == audioplayers.PlayerState.playing;
        });
      });
    } catch (e) {
      debugPrint('設置音訊播放器監聽器時出錯: $e');
    }
  }

  void _setupVadHandler() {
    _vadHandler.onSpeechStart.listen((_) {
      debugPrint('Speech detected.');
      if (mounted) {
        setState(() {
          _isSpeaking = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('語音檢測開始'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    });

    _vadHandler.onSpeechEnd.listen((List<double> samples) {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
        recordings.add(Recording(
          samples: samples,
          type: RecordingType.speech,
        ));
        // 清空音訊幀緩衝區
        _audioFrameBuffer.clear();
      });
      debugPrint(
          'Speech ended, recording added. Length: ${samples.length} samples');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '語音檢測結束，錄音長度: ${(samples.length / 16000).toStringAsFixed(1)} 秒'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });

    _vadHandler.onVADMisfire.listen((_) {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
        recordings.add(Recording(type: RecordingType.misfire));
        // 清空音訊幀緩衝區
        _audioFrameBuffer.clear();
      });
      debugPrint('VAD misfire detected.');
    });

    _vadHandler.onError.listen((String message) {
      debugPrint('Error: $message');
    });

    // 新增對音訊幀事件的處理
    _vadHandler.onAudioFrame.listen((Uint8List audioData) {
      // 更新音量顯示
      _updateVolumeLevel(audioData);

      // 如果正在說話，則將音訊幀添加到緩衝區
      if (_isSpeaking || submitUserSpeechOnPause) {
        _audioFrameBuffer.add(audioData);
      }
    });
  }

  // 重新調整計算音量級別的方法
  void _updateVolumeLevel(Uint8List audioData) {
    if (audioData.isEmpty) return;

    final int16List = audioData.buffer.asInt16List();
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

    if (mounted) {
      setState(() {
        currentDecibel = db;
      });
    }
  }

  Future<void> _initializeAudioPlayer() async {
    try {
      _audioPlayer = audioplayers.AudioPlayer();
      // 不再調用 setAudioContext 方法，因為這可能導致 MissingPluginException
    } catch (e) {
      debugPrint('初始化音訊播放器時出錯: $e');
    }
  }

  Future<void> _playRecording(Recording recording, int index) async {
    if (recording.type == RecordingType.misfire) return;

    try {
      if (_currentlyPlayingIndex == index && _isPlaying) {
        try {
          await _audioPlayer?.pause();
        } catch (e) {
          debugPrint('暫停音訊時出錯: $e');
        }
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
        });
      } else {
        if (_currentlyPlayingIndex != index) {
          try {
            String uri = AudioUtils.createWavUrl(recording.samples!);
            await _audioPlayer?.play(audioplayers.UrlSource(uri));
          } catch (e) {
            debugPrint('播放音訊時出錯: $e');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('播放音訊時出錯: ${e.toString().split('\n')[0]}'),
                duration: const Duration(seconds: 2),
              ),
            );
            return;
          }
          if (!mounted) return;
          setState(() {
            _currentlyPlayingIndex = index;
            _isPlaying = true;
          });
        } else {
          try {
            await _audioPlayer?.resume();
          } catch (e) {
            debugPrint('恢復播放時出錯: $e');
          }
          if (!mounted) return;
          setState(() {
            _isPlaying = true;
          });
        }
      }
    } catch (e) {
      debugPrint('播放錄音時出錯: $e');
    }
  }

  Future<void> _seekTo(Duration position) async {
    try {
      await _audioPlayer?.seek(position);
      if (!mounted) return;
      setState(() {
        _position = position;
      });
    } catch (e) {
      debugPrint('調整播放位置時出錯: $e');
    }
  }

  @override
  void dispose() {
    try {
      _audioPlayer?.dispose();
    } catch (e) {
      debugPrint('釋放音訊播放器資源時出錯: $e');
    }

    try {
      _vadHandler.dispose();
    } catch (e) {
      debugPrint('釋放 VAD 處理器資源時出錯: $e');
    }
    super.dispose();
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
    final bool isMisfire = recording.type == RecordingType.misfire;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Column(
        children: [
          ListTile(
            leading: isMisfire
                ? const CircleAvatar(
                    backgroundColor: Colors.red,
                    child:
                        Icon(Icons.warning_amber_rounded, color: Colors.white),
                  )
                : CircleAvatar(
                    backgroundColor: Colors.blue[900],
                    child: Icon(
                      isCurrentlyPlaying && _isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: Colors.blue[100],
                    ),
                  ),
            title: Text(
              isMisfire ? 'Misfire Event' : 'Recording ${index + 1}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isMisfire ? Colors.red[300] : null,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatTimestamp(recording.timestamp)),
                if (!isMisfire)
                  Text(
                    '${(recording.samples!.length / 16000).toStringAsFixed(1)} seconds',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
              ],
            ),
            onTap: isMisfire ? null : () => _playRecording(recording, index),
          ),
          if (isCurrentlyPlaying && !isMisfire) ...[
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
                      max: _duration.inMilliseconds.toDouble(),
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

  Widget _buildDecibelMeter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('音量', style: TextStyle(fontSize: 16)),
              Text(
                  currentDecibel < -55.0
                      ? "靜音"
                      : "${(-currentDecibel).toStringAsFixed(1)} dB",
                  style: const TextStyle(fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 1 - ((60 + currentDecibel) / 60).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey[800],
              valueColor: AlwaysStoppedAnimation<Color>(
                _getDecibelColor(currentDecibel),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getDecibelColor(double db) {
    if (db < -55) return Colors.grey; // 靜音時顯示灰色
    if (db < -40) return Colors.red;
    if (db < -20) return Colors.yellow;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("VAD Example"),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (isListening) _buildDecibelMeter(), // 加入分貝顯示器
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              itemCount: recordings.length,
              itemBuilder: (context, index) {
                return _buildRecordingItem(recordings[index], index);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.black,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  spreadRadius: 1,
                  blurRadius: 10,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('保留手動停止時的音訊'),
                  subtitle: const Text('啟用後，手動停止錄音時會保留已錄製的音訊'),
                  value: submitUserSpeechOnPause,
                  activeColor: Colors.blue,
                  onChanged: (value) {
                    setState(() {
                      submitUserSpeechOnPause = value;
                      if (isListening) {
                        _vadHandler.stopListening();
                        _vadHandler.startListening(
                          frameSamples: frameSamples,
                          submitUserSpeechOnPause: submitUserSpeechOnPause,
                          preSpeechPadFrames: preSpeechPadFrames,
                          redemptionFrames: redemptionFrames,
                          warmupFrames: 15,
                        );
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    setState(() {
                      if (isListening) {
                        _vadHandler.stopListening();
                        // 不在這裡調用 _saveCurrentAudioBuffer，讓 VAD 套件的 forceEndSpeech 處理
                        // 如果用戶正在講話，forceEndSpeech 會觸發 onSpeechEnd 事件
                        // 如果用戶沒有講話，則不需要保存音頻
                      } else {
                        _vadHandler.startListening(
                          frameSamples: frameSamples,
                          submitUserSpeechOnPause: submitUserSpeechOnPause,
                          preSpeechPadFrames: preSpeechPadFrames,
                          redemptionFrames: redemptionFrames,
                          warmupFrames: 15,
                        );
                      }
                      isListening = !isListening;
                    });
                  },
                  icon: Icon(isListening ? Icons.stop : Icons.mic),
                  label:
                      Text(isListening ? "Stop Listening" : "Start Listening"),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 8),
                if (isListening)
                  ElevatedButton.icon(
                    onPressed: () {
                      _vadHandler.stopListening();
                      // 只有在用戶正在講話時才保存音頻
                      // 如果 submitUserSpeechOnPause 為 false，則不保存音頻
                      if (!submitUserSpeechOnPause) {
                        _audioFrameBuffer.clear();
                      }
                      // 不在這裡調用 _saveCurrentAudioBuffer，讓 VAD 套件的 forceEndSpeech 處理
                      setState(() {
                        isListening = false;
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              submitUserSpeechOnPause && _isSpeaking
                                  ? '已手動停止錄音，音訊已保存'
                                  : '已手動停止錄音，音訊未保存',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.pan_tool),
                    label: const Text("測試手動停止"),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: Colors.orange,
                    ),
                  ),
                const SizedBox(height: 8),
                if (isListening)
                  ElevatedButton.icon(
                    onPressed: _simulateSpeech,
                    icon: const Icon(Icons.record_voice_over),
                    label: const Text("模擬語音檢測"),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: Colors.green,
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: isWindowsPlatform
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Windows 平台上不需要請求麥克風權限'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      : () async {
                          final status = await Permission.microphone.request();
                          debugPrint("Microphone permission status: $status");
                        },
                  icon: const Icon(Icons.settings_voice),
                  label: const Text("Request Microphone Permission"),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 添加一個函數來模擬語音檢測
  Future<void> _simulateSpeech() async {
    if (!isListening) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('請先開始錄音'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('模擬語音檢測中...請說話'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
