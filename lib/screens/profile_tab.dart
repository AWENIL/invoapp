import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import '../providers/app_providers.dart';
import '../theme/driver_auth_theme.dart';
import 'driver_notifications_screen.dart';
import 'driver_personal_info_screen.dart';
import 'driver_support_screen.dart';

String _regionSubtitle(Map<String, dynamic> profile) {
  final r = profile['region'];
  if (r is Map) {
    final t = r['title']?.toString().trim();
    if (t != null && t.isNotEmpty) return '$t, Казахстан';
  }
  return 'Казахстан';
}

String _initials(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final s = parts.single;
    return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
  }
  return ('${parts.first[0]}${parts.last[0]}').toUpperCase();
}

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final hubBg = theme.brightness == Brightness.light
        ? const Color(0xFFF2F2F7)
        : theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: hubBg,
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) {
          if (s == null) return const SizedBox.shrink();
          final name = s.name;
          final profile = s.profile;

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Text(
                  'Профиль',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: DriverAuthColors.primary.withValues(alpha: 0.15),
                        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _initials(name),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: DriverAuthColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _regionSubtitle(profile),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _hubTile(
                  context,
                  icon: Icons.person_outline_rounded,
                  title: 'Персональная информация',
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const DriverPersonalInfoScreen()),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _hubTile(
                  context,
                  icon: Icons.support_agent_rounded,
                  title: 'Служба поддержки',
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const DriverSupportScreen()),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _hubTile(
                  context,
                  icon: Icons.notifications_none_rounded,
                  title: 'Уведомления',
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const DriverNotificationsScreen()),
                    );
                  },
                ),
                const SizedBox(height: 36),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    await ref.read(sessionProvider.notifier).logout();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded, color: DriverAuthColors.error, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Выход',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: DriverAuthColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

  Widget _hubTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final surface = theme.cardTheme.color ?? theme.colorScheme.surface;
    final border = theme.colorScheme.outline.withValues(alpha: 0.22);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.onSurface.withValues(alpha: 0.75)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              trailing ??
                  Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
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
