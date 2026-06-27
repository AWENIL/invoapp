import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/app_providers.dart';
import '../theme/driver_auth_theme.dart';
import 'order_detail_screen.dart';

String _shortName(Map<String, dynamic> order) {
  final flat = order['passenger_name']?.toString().trim();
  if (flat == null || flat.isEmpty) return 'Пассажир';
  final parts = flat.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (parts.length == 1) return parts[0];
  return '${parts[0]} ${parts[1][0].toUpperCase()}.';
}

String _pickupTime(Map<String, dynamic> order) {
  final raw = order['desired_pickup_time']?.toString();
  if (raw == null) return '';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  return DateFormat('HH:mm').format(dt.toLocal());
}

/// Вкладка «Поездка»: текущий заказ + компактный список следующих.
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
          final nextOrders = orders.length > 1 ? orders.sublist(1) : <Map<String, dynamic>>[];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: OrderDetailScreen(
                  key: ValueKey<String>(id),
                  orderId: id,
                  embeddedInShell: true,
                ),
              ),
              if (nextOrders.isNotEmpty)
                _NextOrdersPanel(
                  orders: nextOrders,
                  onTapOrder: (order) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Сначала завершите текущую поездку'),
                      ),
                    );
                    final nextId = order['id']?.toString() ?? '';
                    if (nextId.isEmpty) return;
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => OrderDetailScreen(orderId: nextId),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NextOrdersPanel extends StatelessWidget {
  const _NextOrdersPanel({
    required this.orders,
    required this.onTapOrder,
  });

  final List<Map<String, dynamic>> orders;
  final void Function(Map<String, dynamic> order) onTapOrder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Следующие заказы',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...orders.map((order) {
                final qIdx = (order['queue_index'] as num?)?.toInt();
                final pickup = order['pickup_title']?.toString() ?? '—';
                final time = _pickupTime(order);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: DriverAuthColors.background,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onTapOrder(order),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            if (qIdx != null)
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: DriverAuthColors.primary.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$qIdx',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: DriverAuthColors.primary,
                                  ),
                                ),
                              ),
                            if (qIdx != null) const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _shortName(order),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    time.isNotEmpty ? '$time · $pickup' : pickup,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: DriverAuthColors.secondaryText,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: Colors.grey.shade500),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
