import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

final _statsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(invoApiProvider).getStatistics();
});

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final stats = ref.watch(_statsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) {
          if (s == null) return const SizedBox.shrink();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(s.name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('На линии'),
                value: s.isOnline,
                onChanged: (v) async {
                  try {
                    await ref.read(invoApiProvider).patchOnlineStatus(v);
                    await ref.read(sessionProvider.notifier).refreshProfile();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
              ),
              const Divider(),
              stats.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Статистика: $e'),
                data: (st) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Рейтинг: ${st['rating'] ?? "—"}'),
                      Text('Заказов сегодня: ${st['today_completed_orders'] ?? "—"}'),
                      Text('Всего завершено: ${st['total_completed_orders'] ?? "—"}'),
                      Text('Принятие: ${st['acceptance_rate'] ?? "—"}'),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () async {
                  await ref.read(sessionProvider.notifier).logout();
                },
                child: const Text('Выйти'),
              ),
            ],
          );
        },
      ),
    );
  }
}
