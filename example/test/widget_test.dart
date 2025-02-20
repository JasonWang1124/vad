// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:vad_example/main.dart';

void main() {
  testWidgets('VAD Example App Test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // 驗證應用程式標題
    expect(find.text('VAD Example'), findsOneWidget);

    // 驗證主要按鈕
    expect(find.text('Start Listening'), findsOneWidget);
    expect(find.text('Request Microphone Permission'), findsOneWidget);
  });
}
