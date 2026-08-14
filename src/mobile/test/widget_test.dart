import 'package:flutter_test/flutter_test.dart';

import 'package:orderxpay_mobile/main.dart';

void main() {
  testWidgets('signed-out app boots to the onboarding screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OrderxPayApp(startSignedIn: false));

    expect(find.text('Business name'), findsOneWidget);
    expect(find.text('Mobile number'), findsOneWidget);
    expect(find.text('Send OTP'), findsOneWidget);
  });
}
