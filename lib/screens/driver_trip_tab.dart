import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import 'order_detail_screen.dart';

/// Вкладка «Поездка»: сценарий текущего заказа — первый в отсортированном списке активных.
class DriverTripTab extends ConsumerWidget {
  const DriverTripTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(driverOrdersProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
        data: (orders) {
          if (orders.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Нет активной поездки.\nВыберите заказ на вкладке «Заказ» или дождитесь назначения.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    height: 1.4,
                  ),
                ),
              ),
            );
          }
          final id = orders.first['id']?.toString() ?? '';
          if (id.isEmpty) {
            return const Center(child: Text('Некорректные данные заказа'));
          }
          return OrderDetailScreen(
            key: ValueKey<String>(id),
            orderId: id,
            embeddedInShell: true,
          );
        },
      ),
    );
  }
}
