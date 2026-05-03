import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/app_providers.dart';
import '../widgets/driver_order_complaint_sheet.dart';
import 'order_detail_screen.dart';

String _statusLabelRu(String code) {
  const labels = {
    'completed': 'Завершено',
    'cancelled': 'Отменено',
    'no_show': 'Неявка',
    'incident': 'Инцидент',
    'rejected': 'Отклонён',
    'draft': 'Черновик',
    'submitted': 'Отправлен',
    'awaiting_dispatcher_decision': 'На решении',
    'created': 'Создан',
    'matching': 'Подбор',
    'active_queue': 'В очереди',
    'offered': 'Предложение',
  };
  return labels[code] ?? code;
}

( Color bg, Color fg ) _statusBadgeColors(String status, ColorScheme scheme) {
  switch (status) {
    case 'completed':
      return (const Color(0xFFFFE5E0), const Color(0xFFC62828));
    case 'cancelled':
    case 'rejected':
    case 'no_show':
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    default:
      return (scheme.surfaceContainerHighest, scheme.onSurface);
  }
}

String _orderDisplayNo(String id) {
  final parts = id.split('-');
  if (parts.length >= 5) {
    final a = parts[1].length >= 2 ? parts[1].substring(0, 2) : parts[1];
    final b = parts[4].length >= 2 ? parts[4].substring(parts[4].length - 2) : parts[4];
    return '№${a.toUpperCase()}-${b.toUpperCase()}';
  }
  if (id.length <= 12) return '№$id';
  return '№${id.substring(0, 6)}…${id.substring(id.length - 2)}';
}

String _historyWhenLine(Map<String, dynamic> o) {
  final raw = o['completed_at'] ?? o['desired_pickup_time'] ?? o['created_at'];
  if (raw == null || raw.toString().isEmpty) return '';
  final dt = DateTime.tryParse(raw.toString());
  if (dt == null) return raw.toString();
  final local = dt.toLocal();
  final now = DateTime.now();
  if (local.year == now.year && local.month == now.month && local.day == now.day) {
    return 'Сегодня · ${DateFormat('HH:mm').format(local)}';
  }
  return DateFormat('d.MM.yyyy · HH:mm').format(local);
}

class DriverHistoryTab extends ConsumerWidget {
  const DriverHistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    const primaryOrange = Color(0xFFFF6B44);
    final async = ref.watch(driverHistoryOrdersProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
        data: (orders) {
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(driverHistoryOrdersProvider),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'История поездок',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Жалобу можно подать в течение 7 дней после завершения. Видео хранится столько же.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            height: 1.4,
                          ),
                        ),
                      ],
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
                          'Пока нет записей',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final o = orders[i];
                          final id = o['id']?.toString() ?? '';
                          final status = o['status']?.toString() ?? '';
                          final pickup = o['pickup_title']?.toString() ?? '';
                          final dropObj = o['dropoff_object_name']?.toString().trim();
                          final dropTitle = o['dropoff_title']?.toString() ?? '';
                          final dropLine = (dropObj != null && dropObj.isNotEmpty) ? dropObj : dropTitle;
                          final timeLine = _historyWhenLine(o);
                          final w = o['waiting_time_minutes'];
                          final durStr = w is num && w > 0 ? '${w.round()} мин' : '—';
                          final badgeColors = _statusBadgeColors(status, theme.colorScheme);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Material(
                              color: theme.cardTheme.color ?? theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () async {
                                  await Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) => OrderDetailScreen(orderId: id),
                                    ),
                                  );
                                  ref.invalidate(driverHistoryOrdersProvider);
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: theme.colorScheme.outline.withValues(alpha: 0.22),
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              timeLine,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: badgeColors.$1,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              _statusLabelRu(status),
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: badgeColors.$2,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Откуда',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        pickup.isNotEmpty ? pickup : '—',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Куда',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        dropLine.isNotEmpty ? dropLine : '—',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${_orderDisplayNo(id)} · $durStr',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                              ),
                                            ),
                                          ),
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => openDriverOrderComplaint(context, id),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Жалоба',
                                                  style: theme.textTheme.labelLarge?.copyWith(
                                                    color: primaryOrange,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Icon(Icons.chevron_right, size: 20, color: primaryOrange),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: orders.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
