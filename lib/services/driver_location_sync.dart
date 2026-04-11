import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../providers/app_providers.dart';

final driverLocationSyncProvider =
    NotifierProvider<DriverLocationSyncNotifier, bool>(DriverLocationSyncNotifier.new);

class DriverLocationSyncNotifier extends Notifier<bool> {
  Timer? _timer;
  bool _starting = false;

  @override
  bool build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return false;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _starting = false;
    state = false;
  }

  Future<void> start() async {
    if (_timer != null || _starting) return;
    _starting = true;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      final session = ref.read(sessionProvider).valueOrNull;
      if (session == null || !session.isOnline) return;

      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(_push());
      });
      await _push();
      state = true;
    } finally {
      _starting = false;
    }
  }

  Future<void> _push() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      await ref.read(invoApiProvider).patchLocation(pos.latitude, pos.longitude);
    } catch (_) {}
  }
}

/// Поддерживает фоновую отправку координат, пока сессия «на линии».
class SessionLocationBinder extends ConsumerStatefulWidget {
  const SessionLocationBinder({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SessionLocationBinder> createState() => _SessionLocationBinderState();
}

class _SessionLocationBinderState extends ConsumerState<SessionLocationBinder> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSession(ref.read(sessionProvider).valueOrNull);
    });
  }

  void _syncSession(DriverSession? s) {
    if (s == null || !s.isOnline) {
      ref.read(driverLocationSyncProvider.notifier).stop();
    } else {
      unawaited(ref.read(driverLocationSyncProvider.notifier).start());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<DriverSession?>>(sessionProvider, (prev, next) {
      next.whenData(_syncSession);
    });
    return widget.child;
  }
}
