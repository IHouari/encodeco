
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:encdec_app/main.dart';

void main() {
  testWidgets('Title verification test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the title is correct.
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.title, 'EncDec AES-256-GCM');
  });
}
