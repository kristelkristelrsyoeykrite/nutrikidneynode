import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nutri_kidney/main.dart'; // Make sure this matches your project name

void main() {
  testWidgets('Login screen loads correctly smoke test', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const NutriKidneyApp());

    // Verify that the main elements of our login screen are present.
    // We expect to find the "Log in" text on the screen.
    expect(find.text('Log in'), findsWidgets);

    // We expect to find the email and password labels.
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);

    // We expect NOT to find the old counter app elements.
    expect(find.byIcon(Icons.add), findsNothing);
  });
}
