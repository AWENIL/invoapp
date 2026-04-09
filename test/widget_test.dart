import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:invo_driver/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: InvoDriverApp()));
    await tester.pump();
    expect(find.textContaining('Invotaxi'), findsWidgets);
  });
}
