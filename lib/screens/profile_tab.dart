import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import '../providers/app_providers.dart';
import '../services/driver_location_sync.dart';
import 'edit_driver_profile_screen.dart';

String _driverStatusLabelRu(String? code) {
  switch (code) {
    case 'offline':
      return 'Офлайн';
    case 'online_idle':
      return 'На линии, свободен';
    case 'offered':
      return 'Получено предложение';
    case 'enroute_to_pickup':
      return 'Едет к подаче';
    case 'on_trip':
      return 'В поездке';
    case 'paused':
      return 'Перерыв';
    default:
      return code ?? '—';
  }
}

String? _formatFractionAsPercent(dynamic v) {
  if (v == null) return null;
  if (v is num) return '${(v * 100).round()}%';
  return null;
}

String _ratingLine(DriverSession s, Map<String, dynamic>? st) {
  final pr = s.ratingFromProfile;
  if (pr != null) return pr.toStringAsFixed(1);
  final r = st?['rating'];
  if (r is num) return r.toStringAsFixed(1);
  return '—';
}

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final stats = ref.watch(driverStatisticsProvider);
    final locationSync = ref.watch(driverLocationSyncProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) {
          if (s == null) return const SizedBox.shrink();
          return RefreshIndicator(
            onRefresh: () async {
              await ref.read(sessionProvider.notifier).refreshProfile();
              ref.invalidate(driverStatisticsProvider);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(s.name, style: theme.textTheme.headlineSmall),
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
                if (s.isOnline && !locationSync)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Включите доступ к геолокации в настройках устройства — иначе диспетчер не увидит ваше положение.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Мои данные', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        _ProfileInfoRow(label: 'Телефон', value: s.phone ?? '—'),
                        _ProfileInfoRow(label: 'Регион', value: s.regionTitle ?? '—'),
                        _ProfileInfoRow(label: 'Автомобиль', value: s.carModel),
                        _ProfileInfoRow(label: 'Госномер', value: s.plateNumber),
                        _ProfileInfoRow(
                          label: 'Вместимость',
                          value: s.capacity != null ? '${s.capacity} мест' : '—',
                        ),
                        if (s.lastLocationUpdate != null)
                          _ProfileInfoRow(
                            label: 'Координаты переданы',
                            value: DateFormat('dd.MM.yyyy HH:mm').format(s.lastLocationUpdate!),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Редактировать данные'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => EditDriverProfileScreen(
                          initialProfile: Map<String, dynamic>.from(s.profile),
                        ),
                      ),
                    );
                    if (context.mounted) {
                      await ref.read(sessionProvider.notifier).refreshProfile();
                      ref.invalidate(driverStatisticsProvider);
                    }
                  },
                ),
                const Divider(height: 32),
                stats.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Статистика: $e'),
                  data: (st) {
                    final statusCode = s.statusFromProfile ?? st['status']?.toString();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Статистика', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        _ProfileInfoRow(
                          label: 'Рейтинг',
                          value: _ratingLine(s, st),
                        ),
                        _ProfileInfoRow(
                          label: 'Статус',
                          value: _driverStatusLabelRu(statusCode),
                        ),
                        _ProfileInfoRow(
                          label: 'Заказов сегодня',
                          value: '${st['today_completed_orders'] ?? "—"}',
                        ),
                        _ProfileInfoRow(
                          label: 'Всего завершено',
                          value: '${st['total_completed_orders'] ?? "—"}',
                        ),
                        _ProfileInfoRow(
                          label: 'Принятие предложений',
                          value: _formatFractionAsPercent(st['acceptance_rate']) ?? '—',
                        ),
                        _ProfileInfoRow(
                          label: 'Отмены после принятия',
                          value: _formatFractionAsPercent(st['cancel_rate']) ?? '—',
                        ),
                        _ProfileInfoRow(
                          label: 'Предложений за час',
                          value: '${st['offers_last_60min'] ?? "—"}',
                        ),
                        _ProfileInfoRow(
                          label: 'Заказов за час',
                          value: '${st['orders_last_60min'] ?? "—"}',
                        ),
                      ],
                    );
                  },
                ),
                if (dispatchPhoneTelUri.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.phone_in_talk_outlined),
                    title: const Text('Связь с диспетчером'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () async {
                      final uri = Uri.parse(dispatchPhoneTelUri);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                ],
                const SizedBox(height: 16),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox.shrink();
                    final p = snap.data!;
                    return Text(
                      'Версия ${p.version} (${p.buildNumber})',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
            ),
          );
        },
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
