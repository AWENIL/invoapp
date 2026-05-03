import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/driver_auth_theme.dart';

String _phoneFromProfile(Map<String, dynamic> profile) {
  final u = profile['user'];
  if (u is Map) {
    final p = u['phone']?.toString().trim();
    if (p != null && p.isNotEmpty) return p;
  }
  return '—';
}

String _regionLine(Map<String, dynamic> profile) {
  final r = profile['region'];
  if (r is Map) {
    final t = r['title']?.toString().trim();
    if (t != null && t.isNotEmpty) return '$t, Казахстан';
  }
  return 'Казахстан';
}

String _shortDisplayName(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return 'Водитель';
  if (parts.length == 1) return parts.first;
  final last = parts.last;
  final initial = last.isNotEmpty ? '${last[0].toUpperCase()}.' : '';
  return '${parts.first} $initial'.trim();
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

class DriverPersonalInfoScreen extends ConsumerWidget {
  const DriverPersonalInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionProvider);
    return sessionAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (s) {
        if (s == null) {
          return const Scaffold(body: SizedBox.shrink());
        }
        return _PersonalInfoBody(profile: s.profile);
      },
    );
  }
}

class _PersonalInfoBody extends StatelessWidget {
  const _PersonalInfoBody({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (profile['name'] ?? '') as String? ?? 'Водитель';
    final car = (profile['car_model'] ?? '') as String? ?? '';
    final plate = (profile['plate_number'] ?? '') as String? ?? '';
    final vehicleLine = [car, plate].where((e) => e.isNotEmpty).join(' · ');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Персональная информация'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: DriverAuthColors.primary.withValues(alpha: 0.15),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(name),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: DriverAuthColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _shortDisplayName(name),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _phoneFromProfile(profile),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _regionLine(profile),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          _InfoCard(
            icon: Icons.directions_car_rounded,
            label: 'Автомобиль',
            value: vehicleLine.isEmpty ? '—' : vehicleLine,
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.badge_outlined,
            label: 'Водительские права',
            value: 'Уточните у диспетчера',
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            icon: Icons.workspace_premium_outlined,
            label: 'Сертификат',
            value: 'Уточните у диспетчера',
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
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
    final iconBg = DriverAuthColors.primary.withValues(alpha: 0.12);
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
              color: iconBg,
            ),
            child: Icon(icon, color: DriverAuthColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
