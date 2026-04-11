import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../order_list_sort.dart';
import '../order_status_labels.dart';
import '../providers/app_providers.dart';
import 'order_detail_screen.dart';

String _filterChipLabel(DriverOrdersListFilter f) {
  switch (f) {
    case DriverOrdersListFilter.all:
      return 'Все';
    case DriverOrdersListFilter.active:
      return 'Активные';
    case DriverOrdersListFilter.completed:
      return 'Завершённые';
    case DriverOrdersListFilter.cancelled:
      return 'Отменённые';
  }
}

String _emptyMessage(DriverOrdersListFilter f) {
  switch (f) {
    case DriverOrdersListFilter.all:
      return 'Нет заказов';
    case DriverOrdersListFilter.active:
      return 'Нет активных заказов';
    case DriverOrdersListFilter.completed:
      return 'Нет завершённых заказов';
    case DriverOrdersListFilter.cancelled:
      return 'Нет отменённых заказов';
  }
}

class OrdersTab extends ConsumerStatefulWidget {
  const OrdersTab({super.key});

  @override
  ConsumerState<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends ConsumerState<OrdersTab> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _applySearch(
    List<Map<String, dynamic>> orders,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return orders;
    return orders.where((o) {
      final pickup = o['pickup_title']?.toString().toLowerCase() ?? '';
      final drop = o['dropoff_title']?.toString().toLowerCase() ?? '';
      final id = o['id']?.toString().toLowerCase() ?? '';
      return pickup.contains(q) || drop.contains(q) || id.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(driverOrdersProvider);
    final filter = ref.watch(driverOrdersListFilterProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Мои заказы')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Поиск по адресу или номеру',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: DriverOrdersListFilter.values.map((f) {
                final selected = filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: FilterChip(
                    label: Text(_filterChipLabel(f)),
                    selected: selected,
                    onSelected: (_) {
                      ref.read(driverOrdersListFilterProvider.notifier).state = f;
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (orders) {
                final sorted = List<Map<String, dynamic>>.from(orders);
                sortDriverOrders(sorted);
                final filtered = _applySearch(sorted, _searchController.text);
                if (filtered.isEmpty) {
                  final msg = orders.isEmpty
                      ? _emptyMessage(filter)
                      : 'Ничего не найдено по запросу';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        msg,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(driverOrdersProvider);
                    ref.invalidate(driverActiveOrderProvider);
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final o = filtered[i];
                      final id = o['id']?.toString() ?? '';
                      final pickup = o['pickup_title']?.toString() ?? '';
                      final drop = o['dropoff_title']?.toString() ?? '';
                      final st = o['status']?.toString() ?? '';
                      final time = o['desired_pickup_time']?.toString();
                      String? timeLabel;
                      if (time != null) {
                        try {
                          timeLabel = DateFormat('dd.MM.yyyy HH:mm')
                              .format(DateTime.parse(time).toLocal());
                        } catch (_) {
                          timeLabel = time;
                        }
                      }
                      final statusLabel = orderStatusLabelRu(st);
                      final isDone = st == 'completed' || st == 'cancelled';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => OrderDetailScreen(orderId: id),
                              ),
                            );
                            ref.invalidate(driverOrdersProvider);
                            ref.invalidate(driverActiveOrderProvider);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      isDone ? Icons.check_circle_outline : Icons.local_taxi_outlined,
                                      size: 22,
                                      color: isDone ? scheme.outline : scheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            pickup,
                                            style: theme.textTheme.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            drop,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right, size: 22),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Chip(
                                      label: Text(statusLabel),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      labelStyle: theme.textTheme.labelMedium,
                                    ),
                                    if (timeLabel != null)
                                      Text(
                                        timeLabel,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
