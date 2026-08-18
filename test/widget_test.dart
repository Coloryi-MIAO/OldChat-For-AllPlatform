import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oldchat_for_allplatform/main.dart' as app;

void main() {
  testWidgets('App launches without crashing', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();

    // 只要不崩溃，就算通过
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}