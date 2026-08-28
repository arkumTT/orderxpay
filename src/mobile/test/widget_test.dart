import 'package:flutter_test/flutter_test.dart';

import 'package:orderxpay_mobile/main.dart';

void main() {
  testWidgets('signed-out app boots to the login screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OrderxPayApp(startSignedIn: false));

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.textContaining('Register'), findsOneWidget);
  });
}
