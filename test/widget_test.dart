import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kogo_voice_learning/features/activity/presentation/pages/restricted_vocabulary_test_page.dart';

void main() {
  testWidgets('Restricted vocabulary test page loads', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RestrictedVocabularyTestPage(),
      ),
    );

    await tester.pump();

    expect(
      find.text('Restricted Vocabulary Test'),
      findsOneWidget,
    );
  });
}