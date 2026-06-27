import 'package:flutter_test/flutter_test.dart';
import 'package:invo_driver/providers/app_providers.dart';

void main() {
  group('filterDriverOrdersForToday', () {
    test('keeps orders with desired_pickup_time today', () {
      final now = DateTime.now();
      final todayPickup = DateTime(now.year, now.month, now.day, 14, 30);
      final tomorrowPickup = todayPickup.add(const Duration(days: 1));

      final orders = [
        {'id': '1', 'desired_pickup_time': todayPickup.toIso8601String()},
        {'id': '2', 'desired_pickup_time': tomorrowPickup.toIso8601String()},
      ];

      final filtered = filterDriverOrdersForToday(orders);
      expect(filtered.map((o) => o['id']), ['1']);
    });

    test('includes orders without pickup time', () {
      final orders = [
        {'id': '1'},
      ];
      expect(filterDriverOrdersForToday(orders), hasLength(1));
    });
  });
}
