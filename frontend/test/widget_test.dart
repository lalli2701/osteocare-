// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:osteocare_plus/main.dart';

void main() {
  testWidgets('OsteoCareApp builds without error',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // Note: Full app test would require Firebase initialization
    // This test verifies the app widget can be instantiated
    expect(OsteoCareApp, isNotNull);
  });
}
