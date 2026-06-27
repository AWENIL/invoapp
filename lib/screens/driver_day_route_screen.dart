import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/app_providers.dart';
import '../theme/driver_auth_theme.dart';
import 'order_detail_screen.dart';

String _passengerLabel(Map<String, dynamic> order) {
  final flat = order['passenger_name']?.toString().trim();
  if (flat != null && flat.isNotEmpty) {
    final parts = flat.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (parts.length == 1) return parts[0];
    return '${parts[0]} ${parts[1][0].toUpperCase()}.';
  }
  return 'Пассажир';
}

String _timeLabel(Map<String, dynamic> order) {
  final raw = order['planned_pickup_time'] ?? order['desired_pickup_time'];
  if (raw == null) return '—';
  final dt = DateTime.tryParse(raw.toString());
  if (dt == null) return raw.toString();
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final hm = DateFormat('HH:mm').format(local);
  if (day == today) return hm;
  if (day == today.add(const Duration(days: 1))) {
    return 'Завтра, $hm';
  }
  return '${DateFormat('d MMM', 'ru').format(local)}, $hm';
}

String _statusLabel(String? code) {
  switch (code) {
    case 'assigned':
      return 'Назначен';
    case 'driver_en_route':
      return 'Еду к подаче';
    case 'arrived_waiting':
      return 'Ожидание';
    case 'ride_ongoing':
      return 'В поездке';
    case 'completed':
      return 'Завершён';
    default:
      return code ?? '—';
  }
}

class DriverDayRouteScreen extends ConsumerWidget {
  const DriverDayRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(driverOrdersProvider);
    final dayRouteAsync = ref.watch(driverDayRouteProvider);
    final dayIndex = dayRouteAsync.maybeWhen(
      data: (route) {
        final orders = route['orders'];
        if (orders is! List) return <String, Map<String, dynamic>>{};
        final map = <String, Map<String, dynamic>>{};
        for (final o in orders) {
          if (o is! Map) continue;
          final id = o['id']?.toString();
          if (id != null && id.isNotEmpty) {
            map[id] = Map<String, dynamic>.from(o);
          }
        }
        return map;
      },
      orElse: () => <String, Map<String, dynamic>>{},
    );
    final currentId = async.maybeWhen(
      data: (orders) => orders.isNotEmpty ? orders.first['id']?.toString() : null,
      orElse: () => dayRouteAsync.maybeWhen(
        data: (route) => route['current_order_id']?.toString(),
        orElse: () => null,
      ),
    );

    return Scaffold(
      backgroundColor: DriverAuthColors.background,
      appBar: AppBar(
        title: const Text('Все заказы'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: DriverAuthColors.primary)),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
        data: (orders) {
          final list = orders;

          if (list.isEmpty) {
            return RefreshIndicator(
              color: DriverAuthColors.primary,
              onRefresh: () async => invalidateDriverOrderQueue(ref),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
                  Center(
                    child: Text(
                      'Нет активных заказов',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: DriverAuthColors.primary,
            onRefresh: () async => invalidateDriverOrderQueue(ref),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 0),
              itemBuilder: (context, i) {
                final order = list[i];
                final id = order['id']?.toString() ?? '';
                final dayMeta = dayIndex[id];
                final merged = dayMeta == null
                    ? order
                    : {...order, ...dayMeta};
                final isCurrent = merged['is_current'] == true || id == currentId;
                final isLast = i == list.length - 1;
                return _TimelineOrderTile(
                  order: merged,
                  isCurrent: isCurrent,
                  isLast: isLast,
                  onTap: id.isEmpty
                      ? null
                      : () async {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => OrderDetailScreen(orderId: id),
                            ),
                          );
                          invalidateDriverOrderQueue(ref);
                        },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _TimelineOrderTile extends StatelessWidget {
  const _TimelineOrderTile({
    required this.order,
    required this.isCurrent,
    required this.isLast,
    this.onTap,
  });

  final Map<String, dynamic> order;
  final bool isCurrent;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = _timeLabel(order);
    final passenger = _passengerLabel(order);
    final pickup = order['pickup_title']?.toString() ?? '—';
    final dropoff = order['dropoff_title']?.toString() ?? '—';
    final status = _statusLabel(order['status']?.toString());
    final batchSize = order['pickup_batch_size'];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 56,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: isCurrent ? DriverAuthColors.primary : Colors.grey.shade400,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: DriverAuthColors.primary.withValues(alpha: 0.35),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Material(
                color: isCurrent ? DriverAuthColors.primary.withValues(alpha: 0.08) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isCurrent
                            ? DriverAuthColors.primary
                            : DriverAuthColors.border.withValues(alpha: 0.65),
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              time,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: isCurrent ? DriverAuthColors.primary : null,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              status,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: DriverAuthColors.secondaryText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          passenger,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text('Откуда: $pickup', style: theme.textTheme.bodySmall),
                        const SizedBox(height: 2),
                        Text('Куда: $dropoff', style: theme.textTheme.bodySmall),
                        if (batchSize is num && batchSize > 1) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: DriverAuthColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Групповая подача · ${batchSize.toInt()}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: DriverAuthColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
