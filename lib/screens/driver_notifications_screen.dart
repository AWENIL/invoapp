import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/driver_profile_extras_providers.dart';
import '../theme/driver_auth_theme.dart';

class DriverNotificationsScreen extends ConsumerWidget {
  const DriverNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = ref.watch(driverNotificationsProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Уведомления'),
      ),
      body: Column(
        children: [
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'Нет уведомлений',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    itemCount: items.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final n = items[i];
                      return _NotificationCard(entry: n);
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: items.isEmpty
                    ? null
                    : () {
                        ref.read(driverNotificationsProvider.notifier).state = [];
                      },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Очистить все уведомления'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.entry});

  final DriverNotificationEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: DriverAuthColors.primary,
            ),
            child: Icon(entry.icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
