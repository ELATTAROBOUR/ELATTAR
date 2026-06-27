import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/main.dart';

void main() {
  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MobileRepairApp());

    // Verify that our login title is displayed.
    expect(find.text('محلات العطار استور'), findsOneWidget);
    expect(find.text('تسجيل الدخول - قسم الصيانة'), findsOneWidget);

    // Verify that login button is present.
    expect(find.byType(ElevatedButton), findsOneWidget);
  });
}
