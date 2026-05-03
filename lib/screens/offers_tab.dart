import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

class OffersTab extends ConsumerWidget {
  const OffersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(driverOffersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Предложения')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (offers) {
          if (offers.isEmpty) {
            return const Center(child: Text('Нет входящих предложений'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(driverOffersProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: offers.length,
              itemBuilder: (context, i) {
                final o = offers[i];
                final offerId = o['offer_id'];
                final pickup = o['pickup_title']?.toString() ?? '';
                final drop = o['dropoff_title']?.toString() ?? '';
                final km = o['distance_km'];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(pickup, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(drop),
                        if (km != null) Text('≈ $km км'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: offerId == null
                                    ? null
                                    : () async {
                                        try {
                                          await ref.read(invoApiProvider).declineOffer(offerId as int);
                                          ref.invalidate(driverOffersProvider);
                                          ref.invalidate(driverOrdersProvider);
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('$e')),
                                            );
                                          }
                                        }
                                      },
                                child: const Text('Отклонить'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: offerId == null
                                    ? null
                                    : () async {
                                        try {
                                          await ref.read(invoApiProvider).acceptOffer(offerId as int);
                                          ref.invalidate(driverOffersProvider);
                                          ref.invalidate(driverOrdersProvider);
                                          ref.invalidate(driverHistoryOrdersProvider);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Заказ принят')),
                                            );
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('$e')),
                                            );
                                          }
                                        }
                                      },
                                child: const Text('Принять'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
