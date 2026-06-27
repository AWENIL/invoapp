import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/invo_api.dart';
import '../services/cabin_recording_service.dart';
import '../services/driver_location_sync.dart';
import '../services/token_storage.dart';

/// Индекс вкладки нижней навигации водителя: 0 «Заказ», 1 «Поездка», 2 «История», 3 «Профиль».
final driverShellTabIndexProvider = StateProvider<int>((ref) => 0);

/// Статусы «активного» заказа (совпадают с `get_active_order` на бэкенде).
const String driverActiveOrderStatuses =
    'assigned,driver_en_route,arrived_waiting,ride_ongoing';

/// Статусы активной поездки — всё остальное из ответа API показываем в «Истории».
const Set<String> driverActiveOrderStatusSet = {
  'assigned',
  'driver_en_route',
  'arrived_waiting',
  'ride_ongoing',
};

int _driverActiveStatusRank(String code) {
  switch (code) {
    case 'ride_ongoing':
      return 0;
    case 'arrived_waiting':
      return 1;
    case 'driver_en_route':
      return 2;
    case 'assigned':
      return 3;
    default:
      return 99;
  }
}

DateTime? _orderDateHint(Map<String, dynamic> o) {
  final raw = o['desired_pickup_time'] ?? o['created_at'];
  return DateTime.tryParse(raw?.toString() ?? '');
}

/// Один порядок для главного списка и вкладки «Поездка» (первый — текущий к исполнению).
List<Map<String, dynamic>> sortDriverActiveOrders(List<Map<String, dynamic>> orders) {
  final copy = orders.map((e) => Map<String, dynamic>.from(e)).toList();
  final hasQueueIndex = copy.any((o) => o['queue_index'] is num);
  if (hasQueueIndex) {
    copy.sort((a, b) {
      final ia = (a['queue_index'] as num?)?.toInt() ?? 999;
      final ib = (b['queue_index'] as num?)?.toInt() ?? 999;
      return ia.compareTo(ib);
    });
    return copy;
  }
  copy.sort((a, b) {
    final sa = a['status']?.toString() ?? '';
    final sb = b['status']?.toString() ?? '';
    final ra = _driverActiveStatusRank(sa);
    final rb = _driverActiveStatusRank(sb);
    if (ra != rb) return ra.compareTo(rb);
    final ta = _orderDateHint(a);
    final tb = _orderDateHint(b);
    if (ta != null && tb != null) return ta.compareTo(tb);
    return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
  });
  return copy;
}

DateTime? _historySortTime(Map<String, dynamic> o) {
  final c = o['completed_at'];
  final d = DateTime.tryParse(c?.toString() ?? '');
  if (d != null) return d;
  return _orderDateHint(o);
}

List<Map<String, dynamic>> sortDriverHistoryOrders(List<Map<String, dynamic>> orders) {
  final copy = orders.map((e) => Map<String, dynamic>.from(e)).toList();
  copy.sort((a, b) {
    final ta = _historySortTime(a);
    final tb = _historySortTime(b);
    if (ta != null && tb != null) return tb.compareTo(ta);
    return (b['id']?.toString() ?? '').compareTo(a['id']?.toString() ?? '');
  });
  return copy;
}

/// Инвалидация очереди и маршрутного листа (единая точка для pull-to-refresh и WebSocket).
void invalidateDriverOrderQueue(WidgetRef ref) {
  ref.invalidate(driverOrderQueueProvider);
  ref.invalidate(driverDayRouteProvider);
}

final driverOrderQueueProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(invoApiProvider).getOrderQueue();
});

final driverDayRouteProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(invoApiProvider).getDayRoute();
});

final driverOrdersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final raw = await ref.watch(driverOrderQueueProvider.future);
  final results = raw['results'];
  if (results is List) {
    final list =
        results.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return sortDriverActiveOrders(list);
  }
  return [];
});

final driverHistoryOrdersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // Без фильтра status на сервере: иначе теряются заказы в других финальных статусах
  // (rejected, стадии до/после реассайна и т.д.). Исключаем только «текущую поездку».
  final raw = await ref.watch(invoApiProvider).getOrders(limit: 500);
  final results = raw['results'];
  if (results is! List) return [];
  final list = <Map<String, dynamic>>[];
  for (final e in results) {
    if (e is! Map) continue;
    final o = Map<String, dynamic>.from(e);
    final st = o['status']?.toString() ?? '';
    if (!driverActiveOrderStatusSet.contains(st)) {
      list.add(o);
    }
  }
  return sortDriverHistoryOrders(list);
});

final driverOffersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final raw = await ref.watch(invoApiProvider).getOffers();
  final results = raw['results'];
  if (results is List) {
    return results.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  return [];
});

/// Текущий незавершённый заказ (если есть). Обновляйте через [ref.invalidate].
final driverActiveOrderProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final raw = await ref.watch(invoApiProvider).getActiveOrder();
  if (raw['has_active_order'] != true) return null;
  return Map<String, dynamic>.from(raw);
});

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final invoApiProvider = Provider<InvoApi>((ref) {
  final t = ref.watch(tokenStorageProvider);
  return InvoApi(t);
});

/// Запись салона во время поездки (один экземпляр на сессию водителя).
final cabinRecordingServiceProvider = ChangeNotifierProvider<CabinRecordingService>((ref) {
  final service = CabinRecordingService(ref.watch(invoApiProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// Статистика водителя для вкладки «Профиль» и др.
final driverStatisticsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(invoApiProvider).getStatistics();
});

class DriverSession {
  DriverSession(this.profile);
  final Map<String, dynamic> profile;

  String get name => (profile['name'] ?? '') as String? ?? 'Водитель';
  bool get isOnline => profile['is_online'] == true;

  String? get phone {
    final u = profile['user'];
    if (u is Map) return u['phone']?.toString();
    return null;
  }

  String? get regionTitle {
    final r = profile['region'];
    if (r is Map) return r['title']?.toString();
    return null;
  }

  String get carModel => profile['car_model']?.toString() ?? '—';
  String get plateNumber => profile['plate_number']?.toString() ?? '—';
  int? get capacity {
    final c = profile['capacity'];
    if (c is int) return c;
    if (c is num) return c.toInt();
    return null;
  }

  DateTime? get lastLocationUpdate {
    final s = profile['last_location_update']?.toString();
    if (s == null || s.isEmpty) return null;
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return null;
    }
  }

  double? get ratingFromProfile {
    final r = profile['rating'];
    if (r is num) return r.toDouble();
    return null;
  }

  String? get statusFromProfile => profile['status']?.toString();
}

final sessionProvider =
    AsyncNotifierProvider<SessionNotifier, DriverSession?>(() => SessionNotifier());

class SessionNotifier extends AsyncNotifier<DriverSession?> {
  void _schedulePushLocationToBackend() {
    Future.microtask(() async {
      try {
        final pos = await DriverLocationSync.getCurrentPositionOrNull();
        if (pos == null) return;
        await ref.read(invoApiProvider).patchLocation(pos.latitude, pos.longitude);
      } catch (_) {}
    });
  }

  @override
  Future<DriverSession?> build() async {
    final api = ref.read(invoApiProvider);
    final storage = ref.read(tokenStorageProvider);
    final access = await storage.readAccess();
    if (access == null || access.isEmpty) return null;
    try {
      final p = await api.getDriverProfile();
      final session = DriverSession(p);
      _schedulePushLocationToBackend();
      return session;
    } catch (_) {
      await storage.clear();
      return null;
    }
  }

  Future<void> refreshProfile() async {
    final api = ref.read(invoApiProvider);
    final p = await api.getDriverProfile();
    state = AsyncData(DriverSession(p));
  }

  Future<void> afterVerify(Map<String, dynamic> verifyResponse) async {
    final api = ref.read(invoApiProvider);
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final p = await api.getDriverProfile();
        state = AsyncData(DriverSession(p));
        _schedulePushLocationToBackend();
        return;
      } catch (e) {
        lastError = e;
      }
    }
    await ref.read(tokenStorageProvider).clear();
    throw lastError is Exception
        ? lastError as Exception
        : Exception(lastError?.toString() ?? 'Профиль недоступен');
  }

  Future<void> logout() async {
    await ref.read(invoApiProvider).logout();
    state = const AsyncData(null);
  }
}
