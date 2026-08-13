import 'package:flutter_test/flutter_test.dart';

import 'package:orderxpay_mobile/main.dart';

void main() {
  testWidgets('app boots to the onboarding screen', (WidgetTester tester) async {
    await tester.pumpWidget(const OrderxPayApp());

    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Business name'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
  });
}
