import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'driver_history_tab.dart';
import 'driver_trip_tab.dart';
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
      body: IndexedStack(
        index: _index,
        children: const [
          OrdersTab(),
          DriverTripTab(),
          DriverHistoryTab(),
          ProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Заказ',
          ),
          NavigationDestination(
            icon: Icon(Icons.place_outlined),
            selectedIcon: Icon(Icons.place),
            label: 'Поездка',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'История',
          ),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Профиль'),
        ],
      ),
    );
  }
}
