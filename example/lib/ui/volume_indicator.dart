import 'package:flutter/material.dart';

/// 音量指示器組件，根據音量級別（0-10）顯示不同的視覺效果
class VolumeIndicator extends StatelessWidget {
  /// 當前音量級別，範圍0-10
  final int volumeLevel;

  /// 指示器的寬度
  final double width;

  /// 指示器的高度
  final double height;

  /// 是否啟用動畫效果
  final bool animate;

  /// 構造函數
  const VolumeIndicator({
    super.key,
    required this.volumeLevel,
    this.width = 200,
    this.height = 40,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(10, (index) {
          final bool isActive = index < volumeLevel;

          // 根據音量級別選擇顏色
          Color barColor;
          if (isActive) {
            if (index < 3) {
              barColor = Colors.green; // 低音量：綠色
            } else if (index < 7) {
              barColor = Colors.orange; // 中音量：橙色
            } else {
              barColor = Colors.red; // 高音量：紅色
            }
          } else {
            barColor = Colors.grey.withOpacity(0.3); // 非活動狀態：灰色
          }

          // 根據索引計算條的高度，使中間的條更高
          final double heightFactor =
              0.5 + (0.5 * (index < 5 ? index : 9 - index)) / 4;

          return AnimatedContainer(
            duration:
                animate ? const Duration(milliseconds: 200) : Duration.zero,
            width: (width - 40) / 10,
            height: height * heightFactor,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}

/// 一個帶有音量級別文字顯示的音量指示器
class VolumeIndicatorWithLabel extends StatelessWidget {
  /// 當前音量級別，範圍0-10
  final double volumeLevel;

  /// 分貝值
  final double decibels;

  /// 指示器的寬度
  final double width;

  /// 構造函數
  const VolumeIndicatorWithLabel({
    super.key,
    required this.volumeLevel,
    required this.decibels,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: width,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Container(
                  width: width * volumeLevel,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.green.shade300,
                        Colors.green.shade500,
                        volumeLevel > 0.7
                            ? Colors.orange
                            : Colors.green.shade500,
                        volumeLevel > 0.9
                            ? Colors.red
                            : (volumeLevel > 0.7
                                ? Colors.orange
                                : Colors.green.shade500),
                      ],
                      stops: const [0.0, 0.6, 0.8, 1.0],
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.2),
                        Colors.white.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.volume_up,
              color: Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              '音量: ${(volumeLevel * 100).toStringAsFixed(0)}% (${decibels.toStringAsFixed(1)} dB)',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
