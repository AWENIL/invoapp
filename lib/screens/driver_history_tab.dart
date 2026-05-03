import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/app_providers.dart';
import 'order_detail_screen.dart';

String _statusLabelRu(String code) {
  const labels = {
    'completed': 'Завершён',
    'cancelled': 'Отменён',
    'no_show': 'Неявка',
    'incident': 'Инцидент',
  };
  return labels[code] ?? code;
}

String _compactOrderId(String id) {
  if (id.length <= 14) return id;
  return '${id.substring(0, 6)}…${id.substring(id.length - 4)}';
}

String _historyTimeLine(Map<String, dynamic> o) {
  final raw = o['completed_at'] ?? o['desired_pickup_time'] ?? o['created_at'];
  if (raw == null || raw.toString().isEmpty) return '';
  final dt = DateTime.tryParse(raw.toString());
  if (dt == null) return raw.toString();
  final local = dt.toLocal();
  return DateFormat('d.MM.yyyy · HH:mm').format(local);
}

class DriverHistoryTab extends ConsumerWidget {
  const DriverHistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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
                          'История',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Завершённые и отменённые заказы.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            height: 1.35,
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
                          final timeLine = _historyTimeLine(o);

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
                                      color: theme.colorScheme.outline.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
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
                                              color: theme.colorScheme.surfaceContainerHighest,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              _statusLabelRu(status),
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        pickup,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '№${_compactOrderId(id)}',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            'Подробнее',
                                            style: theme.textTheme.labelLarge?.copyWith(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.primary),
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
