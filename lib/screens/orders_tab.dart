import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_providers.dart';
import '../theme/driver_auth_theme.dart';
import 'driver_day_route_screen.dart';
import 'driver_order_chat_screen.dart';
import 'offers_tab.dart';
import 'order_detail_screen.dart';

/// Имя в формате макета: «Иван Петрович» → «Иван П.»
String _passengerShortDisplayName(Map<String, dynamic> order) {
  String source = '';
  final flat = order['passenger_name']?.toString().trim();
  if (flat != null && flat.isNotEmpty) {
    source = flat;
  } else {
    final p = order['passenger'];
    if (p is Map) {
      final fn = p['full_name']?.toString().trim();
      if (fn != null && fn.isNotEmpty) source = fn;
    }
  }
  if (source.isEmpty) return 'Пассажир';
  final parts = source.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (parts.length == 1) return parts[0];
  final second = parts[1];
  final initial = second.isNotEmpty ? '${second[0].toUpperCase()}.' : '';
  return '${parts[0]} $initial'.trim();
}

String? _passengerDialPhone(Map<String, dynamic> order) {
  final direct = order['passenger_phone']?.toString().trim();
  if (direct != null && direct.isNotEmpty) return direct;
  final p = order['passenger'];
  if (p is Map) {
    final u = p['user'];
    if (u is Map) {
      final ph = u['phone']?.toString().trim();
      if (ph != null && ph.isNotEmpty) return ph;
    }
  }
  return null;
}

Uri? _telUri(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.isEmpty) return null;
  return Uri(scheme: 'tel', path: digits.startsWith('+') ? digits : digits);
}

/// Бейдж времени как в макете: «Сегодня, 14:30», «5 мая, 10:00»
String _scheduledTimeBadge(Map<String, dynamic> o) {
  final raw = (o['desired_pickup_time'] ?? o['created_at'])?.toString();
  if (raw == null || raw.isEmpty) return '';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final hm = DateFormat('HH:mm').format(local);

  if (day == today) {
    return 'Сегодня, $hm';
  }
  if (day == today.subtract(const Duration(days: 1))) {
    return 'Вчера, $hm';
  }
  final dayPart = DateFormat('d MMMM', 'ru').format(local);
  return '$dayPart, $hm';
}

Map<String, Map<String, dynamic>> _dayRouteOrderIndex(Map<String, dynamic>? route) {
  if (route == null) return {};
  final orders = route['orders'];
  if (orders is! List) return {};
  final map = <String, Map<String, dynamic>>{};
  for (final o in orders) {
    if (o is! Map) continue;
    final id = o['id']?.toString();
    if (id != null && id.isNotEmpty) {
      map[id] = Map<String, dynamic>.from(o);
    }
  }
  return map;
}

(List<Map<String, dynamic>>, List<Map<String, dynamic>>) _splitQueueSections(
  List<Map<String, dynamic>> orders,
) {
  if (orders.isEmpty) return ([], []);
  final hasMeta = orders.any((o) => o['is_current'] == true || o['queue_index'] is num);
  if (!hasMeta) {
    return ([orders.first], orders.sublist(1));
  }
  final current = <Map<String, dynamic>>[];
  final next = <Map<String, dynamic>>[];
  for (final o in orders) {
    if (o['is_current'] == true || (o['queue_index'] as num?)?.toInt() == 1) {
      current.add(o);
    } else {
      next.add(o);
    }
  }
  if (current.isEmpty && orders.isNotEmpty) {
    return ([orders.first], orders.sublist(1));
  }
  return (current, next);
}

/// Круглые действия светло‑кораловые как в UI‑ките.
Widget _circleAction({
  required IconData icon,
  required VoidCallback onTap,
}) {
  return Material(
    color: DriverAuthColors.primary.withValues(alpha: 0.14),
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(icon, color: DriverAuthColors.primary, size: 22),
      ),
    ),
  );
}

class OrdersTab extends ConsumerWidget {
  const OrdersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(driverOrdersProvider);
    final dayRouteAsync = ref.watch(driverDayRouteProvider);
    final dayIndex = dayRouteAsync.maybeWhen(
      data: _dayRouteOrderIndex,
      orElse: () => <String, Map<String, dynamic>>{},
    );
    final subtleBg = DriverAuthColors.background;

    return Scaffold(
      backgroundColor: subtleBg,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: DriverAuthColors.primary)),
        error: (e, _) =>
            Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
        data: (orders) {
          final (currentOrders, nextOrders) = _splitQueueSections(orders);
          final routeDate = dayRouteAsync.maybeWhen(
            data: (r) => r['date']?.toString(),
            orElse: () => null,
          );
          final routeTotal = dayRouteAsync.maybeWhen(
            data: (r) => (r['total_orders'] as num?)?.toInt(),
            orElse: () => orders.length,
          );
          final dateLabel = () {
            final parsed = DateTime.tryParse(routeDate ?? '');
            if (parsed != null) {
              return DateFormat('d MMMM', 'ru').format(parsed);
            }
            return DateFormat('d MMMM', 'ru').format(DateTime.now());
          }();

          return RefreshIndicator(
            color: DriverAuthColors.primary,
            onRefresh: () async => invalidateDriverOrderQueue(ref),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              'Заказы',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Предложения',
                            onPressed: () {
                              Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => const OffersTab(),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.notifications_active_outlined,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (orders.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const DriverDayRouteScreen(),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Icon(Icons.route_rounded, color: DriverAuthColors.primary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Маршрут на $dateLabel',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        '$routeTotal заказов',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: DriverAuthColors.secondaryText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'Весь лист',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: DriverAuthColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.chevron_right, color: DriverAuthColors.primary),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (orders.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Нет активных заказов',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                  )
                else ...[
                  if (currentOrders.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: Text(
                          'Сейчас',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: DriverAuthColors.primary,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      sliver: SliverList.separated(
                        itemCount: currentOrders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _buildOrderCard(
                          context,
                          ref,
                          currentOrders[i],
                          highlightQueue: true,
                          dayIndex: dayIndex,
                        ),
                      ),
                    ),
                  ],
                  if (nextOrders.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: Text(
                          'Далее (${nextOrders.length})',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      sliver: SliverList.separated(
                        itemCount: nextOrders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _buildOrderCard(
                          context,
                          ref,
                          nextOrders[i],
                          highlightQueue: false,
                          dayIndex: dayIndex,
                        ),
                      ),
                    ),
                  ] else
                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> order, {
    required bool highlightQueue,
    required Map<String, Map<String, dynamic>> dayIndex,
  }) {
    final id = order['id']?.toString() ?? '';
    final dayMeta = dayIndex[id];
    final batchSize = dayMeta?['pickup_batch_size'] ?? order['pickup_batch_size'];

    return _DriverOrderCard(
      order: order,
      highlightQueue: highlightQueue,
      pickupBatchSize: batchSize is num ? batchSize.toInt() : null,
      onOpenDetail: () async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => OrderDetailScreen(orderId: id),
          ),
        );
        invalidateDriverOrderQueue(ref);
      },
      onChat: () {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => DriverOrderChatScreen(
              orderId: id,
              passengerName: _passengerShortDisplayName(order),
              passengerPhone: _passengerDialPhone(order),
            ),
          ),
        );
      },
      onPhone: () async {
        final ph = _passengerDialPhone(order);
        if (ph == null || ph.isEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Телефон пассажира не указан')),
            );
          }
          return;
        }
        final u = _telUri(ph);
        if (u != null && await canLaunchUrl(u)) {
          await launchUrl(u);
        }
      },
    );
  }
}

class _DriverOrderCard extends StatelessWidget {
  const _DriverOrderCard({
    required this.order,
    required this.highlightQueue,
    required this.onOpenDetail,
    required this.onChat,
    required this.onPhone,
    this.pickupBatchSize,
  });

  final Map<String, dynamic> order;
  final bool highlightQueue;
  final VoidCallback onOpenDetail;
  final VoidCallback onChat;
  final VoidCallback onPhone;
  final int? pickupBatchSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pickup = order['pickup_title']?.toString() ?? '—';
    final dropoff = order['dropoff_title']?.toString() ?? '—';
    final timeBadge = _scheduledTimeBadge(order);
    final passenger = _passengerShortDisplayName(order);
    final qIdx = (order['queue_index'] as num?)?.toInt();
    final qTotal = (order['queue_total'] as num?)?.toInt();

    final borderColor =
        highlightQueue ? DriverAuthColors.primary : DriverAuthColors.border.withValues(alpha: 0.65);
    final borderWidth = highlightQueue ? 2.0 : 1.0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: highlightQueue ? 0 : 0,
      child: InkWell(
        onTap: onOpenDetail,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: highlightQueue
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Пассажир',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: DriverAuthColors.secondaryText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          passenger,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (qIdx != null && qTotal != null)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: highlightQueue
                            ? DriverAuthColors.primary.withValues(alpha: 0.14)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$qIdx из $qTotal',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: highlightQueue ? DriverAuthColors.primary : null,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _circleAction(icon: Icons.chat_bubble_outline_rounded, onTap: onChat),
                      const SizedBox(width: 10),
                      _circleAction(icon: Icons.phone_rounded, onTap: onPhone),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (timeBadge.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: DriverAuthColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 16,
                          color: DriverAuthColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeBadge,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: DriverAuthColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (pickupBatchSize != null && pickupBatchSize! > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      'Групповая подача · $pickupBatchSize',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              _RoutePointRow(
                icon: Icons.navigation_rounded,
                label: 'Точка посадки',
                value: pickup,
              ),
              const SizedBox(height: 14),
              _RoutePointRow(
                icon: Icons.flag_rounded,
                label: 'Пункт назначения',
                value: dropoff,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutePointRow extends StatelessWidget {
  const _RoutePointRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: DriverAuthColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: DriverAuthColors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: DriverAuthColors.secondaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
