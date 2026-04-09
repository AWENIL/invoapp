import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/app_providers.dart';
import 'order_detail_screen.dart';

class OrdersTab extends ConsumerWidget {
  const OrdersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(driverOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Мои заказы')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('Нет заказов'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(driverOrdersProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              itemBuilder: (context, i) {
                final o = orders[i];
                final id = o['id']?.toString() ?? '';
                final pickup = o['pickup_title']?.toString() ?? '';
                final drop = o['dropoff_title']?.toString() ?? '';
                final st = o['status']?.toString() ?? '';
                final time = o['desired_pickup_time']?.toString();
                String? timeLabel;
                if (time != null) {
                  try {
                    timeLabel = DateFormat('dd.MM HH:mm').format(DateTime.parse(time).toLocal());
                  } catch (_) {
                    timeLabel = time;
                  }
                }
                return Card(
                  child: ListTile(
                    title: Text(pickup, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '$drop\n$st${timeLabel != null ? ' · $timeLabel' : ''}',
                      maxLines: 3,
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OrderDetailScreen(orderId: id),
                        ),
                      );
                      ref.invalidate(driverOrdersProvider);
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
