import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import 'offers_tab.dart';
import 'order_detail_screen.dart';
import 'orders_tab.dart';
import 'profile_tab.dart';

class DriverShell extends ConsumerStatefulWidget {
  const DriverShell({super.key});

  @override
  ConsumerState<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<DriverShell> {
  int _index = 0;
  Timer? _activeOrderPoll;

  @override
  void initState() {
    super.initState();
    _activeOrderPoll = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!mounted) return;
      ref.invalidate(driverActiveOrderProvider);
    });
  }

  @override
  void dispose() {
    _activeOrderPoll?.cancel();
    super.dispose();
  }

  String _statusRu(String code) {
    const labels = {
      'assigned': 'Назначен',
      'driver_en_route': 'Еду к пассажиру',
      'arrived_waiting': 'Ожидаю',
      'ride_ongoing': 'В пути',
      'completed': 'Завершён',
      'cancelled': 'Отменён',
    };
    return labels[code] ?? code;
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(driverActiveOrderProvider);
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          active.when(
            skipLoadingOnReload: true,
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (order) {
              if (order == null) return const SizedBox.shrink();
              final id = order['id']?.toString() ?? '';
              final pickup = order['pickup_title']?.toString() ?? '';
              final st = order['status']?.toString() ?? '';
              final scheme = Theme.of(context).colorScheme;
              return Material(
                color: scheme.primaryContainer.withValues(alpha: 0.4),
                child: InkWell(
                  onTap: id.isEmpty
                      ? null
                      : () async {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => OrderDetailScreen(orderId: id),
                            ),
                          );
                          if (context.mounted) {
                            ref.invalidate(driverActiveOrderProvider);
                            ref.invalidate(driverOrdersProvider);
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Row(
                      children: [
                        Icon(Icons.local_taxi_rounded, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Текущий заказ',
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                      color: scheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_statusRu(st)} · $pickup',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [OrdersTab(), OffersTab(), ProfileTab()],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), label: 'Заказы'),
          NavigationDestination(icon: Icon(Icons.notifications_active_outlined), label: 'Предложения'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Профиль'),
        ],
      ),
    );
  }
}
