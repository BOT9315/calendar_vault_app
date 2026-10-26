import 'package:flutter_test/flutter_test.dart';
import 'package:calendar_vault_app/main.dart';

void main() {
  testWidgets('CalendarVaultApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CalendarVaultApp());
    expect(find.byType(CalendarVaultApp), findsOneWidget);
  });
}
