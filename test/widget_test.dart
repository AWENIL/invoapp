import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:invo_driver/main.dart';
import 'package:invo_driver/providers/app_providers.dart';

/// Без сети: сразу экран входа (не вызываем профиль по токену).
class _NoNetworkSession extends SessionNotifier {
  @override
  Future<DriverSession?> build() async => null;
}

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(_NoNetworkSession.new),
        ],
        child: const InvoDriverApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Invotaxi'), findsWidgets);
  });
}
