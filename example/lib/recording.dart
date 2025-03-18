/// 錄音類型
enum RecordingType {
  /// 語音開始事件
  speechStart,

  /// 實際語音開始事件
  realSpeechStart,

  /// 語音結束事件
  speechEnd,

  /// VAD誤觸發事件
  misfire,

  /// 錯誤事件
  error,

  /// 手動停止事件
  manualStop,

  /// 靜音閥值達到事件
  silenceThresholdReached,
}

/// 錄音類
class Recording {
  /// 音頻樣本
  final List<double>? samples;

  /// 錄音類型
  final RecordingType type;

  /// 時間戳
  final DateTime timestamp;

  /// 構造函數
  Recording({
    this.samples,
    required this.type,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
