import 'package:flutter_test/flutter_test.dart';

import 'package:aptigen_erp/app/app.dart';

void main() {
  testWidgets('App boots to the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const AptigenApp());
    await tester.pump();

    expect(find.byType(AptigenApp), findsOneWidget);
  });
}
