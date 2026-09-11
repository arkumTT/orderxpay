import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orderxpay_mobile/main.dart';

void main() {
  testWidgets('signed-out app boots to the login screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OrderxPayApp(initialRoute: '/login'));

    expect(find.text('Phone or email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.textContaining('Register'), findsOneWidget);
  });

  testWidgets('the login field shows how it is reading the identifier', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OrderxPayApp(initialRoute: '/login'));

    // no hint until something is typed
    expect(find.textContaining('Signing in with'), findsNothing);

    final field = find.widgetWithText(TextFormField, '20 553 7712 or you@business.com');

    await tester.enterText(field, '024 481 2345');
    await tester.pump();
    expect(find.text('Signing in with +233 24 481 2345'), findsOneWidget);

    await tester.enterText(field, 'ama@shop.test');
    await tester.pump();
    expect(find.text('Signing in with your email'), findsOneWidget);

    // an incomplete number falls back to the generic line
    await tester.enterText(field, '024');
    await tester.pump();
    expect(find.text('Signing in with your phone number'), findsOneWidget);
  });

  testWidgets('forgot password is reachable from login and starts in its initial state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OrderxPayApp(initialRoute: '/login'));

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    // Starts on the "enter phone + new password" stage — no code field yet.
    expect(find.text('FORGOT PASSWORD'), findsOneWidget);
    expect(find.text('Send Code'), findsOneWidget);
    expect(find.text('Enter code'), findsNothing);
  });
}
