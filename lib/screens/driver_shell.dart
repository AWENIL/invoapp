import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
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

  @override
  Widget build(BuildContext context) {
    ref.watch(driverActiveOrderProvider);
    final tabIndex = ref.watch(driverShellTabIndexProvider);
    return Scaffold(
      body: IndexedStack(
        index: tabIndex,
        children: const [
          OrdersTab(),
          DriverTripTab(),
          DriverHistoryTab(),
          ProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (i) => ref.read(driverShellTabIndexProvider.notifier).state = i,
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
