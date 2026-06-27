import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/cabin_recording_service.dart';
import '../services/driver_realtime_socket.dart';
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
  DriverRealtimeSocket? _realtimeSocket;

  @override
  void initState() {
    super.initState();
    _activeOrderPoll = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!mounted) return;
      invalidateDriverOrderQueue(ref);
      ref.invalidate(driverActiveOrderProvider);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _connectRealtimeIfNeeded();
      final order = ref.read(driverActiveOrderProvider);
      order.whenData((o) => unawaited(_syncRecording(o)));
    });
  }

  @override
  void dispose() {
    _activeOrderPoll?.cancel();
    _realtimeSocket?.disconnect();
    super.dispose();
  }

  Future<void> _connectRealtimeIfNeeded() async {
    final session = ref.read(sessionProvider).valueOrNull;
    if (session == null) return;
    final driverId = session.profile['id']?.toString();
    if (driverId == null || driverId.isEmpty) return;
    final token = await ref.read(tokenStorageProvider).readAccess();
    if (!mounted || token == null || token.isEmpty) return;
    _realtimeSocket ??= DriverRealtimeSocket();
    _realtimeSocket!.connect(
      driverId: driverId,
      token: token,
      onMessage: (message) {
        if (message['type'] == 'queue_updated') {
          invalidateDriverOrderQueue(ref);
        }
      },
    );
  }

  Future<void> _syncRecording(Map<String, dynamic>? order) async {
    final service = ref.read(cabinRecordingServiceProvider);
    final ok = await service.syncWithOrder(order);
    if (!mounted) return;
    if (!ok &&
        order != null &&
        (orderMapFromActiveResponse(order)?['status']?.toString() == 'ride_ongoing')) {
      final err = service.lastError;
      if (err != null && err.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось начать запись салона: $err')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (prev, next) {
      next.whenData((_) => _connectRealtimeIfNeeded());
    });
    ref.listen(driverActiveOrderProvider, (prev, next) {
      next.whenData((order) => unawaited(_syncRecording(order)));
    });

    final tabIndex = ref.watch(driverShellTabIndexProvider);
    final recording = ref.watch(cabinRecordingServiceProvider);
    final queueCount = ref.watch(driverOrderQueueProvider).maybeWhen(
          data: (q) => (q['count'] as num?)?.toInt() ?? 0,
          orElse: () => 0,
        );
    final showRecBadge = recording.isRecording ||
        recording.pendingUploads > 0 ||
        recording.failedUploads > 0;
    final recLabel = recording.failedUploads > 0
        ? 'Ошибка'
        : recording.pendingUploads > 0
            ? 'Загрузка…'
            : 'REC';

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: tabIndex,
            children: const [
              OrdersTab(),
              DriverTripTab(),
              DriverHistoryTab(),
              ProfileTab(),
            ],
          ),
          if (showRecBadge)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 12,
              child: Material(
                color: recording.failedUploads > 0
                    ? Colors.orange.shade800
                    : Colors.red.shade700,
                borderRadius: BorderRadius.circular(20),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (recording.isRecording)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      if (recording.isRecording) const SizedBox(width: 6),
                      Text(
                        recLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (i) => ref.read(driverShellTabIndexProvider.notifier).state = i,
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: queueCount > 1,
              label: Text('$queueCount'),
              child: const Icon(Icons.home_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: queueCount > 1,
              label: Text('$queueCount'),
              child: const Icon(Icons.home),
            ),
            label: 'Заказ',
          ),
          const NavigationDestination(
            icon: Icon(Icons.place_outlined),
            selectedIcon: Icon(Icons.place),
            label: 'Поездка',
          ),
          const NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'История',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Профиль'),
        ],
      ),
    );
  }
}
