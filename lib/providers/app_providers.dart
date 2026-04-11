import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/invo_api.dart';
import '../services/token_storage.dart';

/// Фильтр списка заказов на вкладке «Заказы».
enum DriverOrdersListFilter {
  all,
  active,
  completed,
  cancelled,
}

extension DriverOrdersListFilterApi on DriverOrdersListFilter {
  /// Параметр `status` для `GET drivers/orders/`; `null` — без фильтра по статусу.
  String? get apiStatusQuery {
    switch (this) {
      case DriverOrdersListFilter.all:
        return null;
      case DriverOrdersListFilter.active:
        return 'assigned,driver_en_route,arrived_waiting,ride_ongoing';
      case DriverOrdersListFilter.completed:
        return 'completed';
      case DriverOrdersListFilter.cancelled:
        return 'cancelled';
    }
  }
}

final driverOrdersListFilterProvider =
    StateProvider<DriverOrdersListFilter>((ref) => DriverOrdersListFilter.all);

final driverOrdersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final filter = ref.watch(driverOrdersListFilterProvider);
  final raw = await ref.watch(invoApiProvider).getOrders(
        status: filter.apiStatusQuery,
        limit: 50,
      );
  final results = raw['results'];
  if (results is List) {
    return results.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  return [];
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
  @override
  Future<DriverSession?> build() async {
    final api = ref.read(invoApiProvider);
    final storage = ref.read(tokenStorageProvider);
    final access = await storage.readAccess();
    if (access == null || access.isEmpty) return null;
    try {
      final p = await api.getDriverProfile();
      return DriverSession(p);
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
    final role = verifyResponse['role'] as String?;
    final hasProfile = verifyResponse['has_profile'] == true;
    if (role != 'driver') {
      await ref.read(tokenStorageProvider).clear();
      throw Exception('Войдите как водитель (текущая роль: ${role ?? "—"})');
    }
    if (!hasProfile) {
      await ref.read(tokenStorageProvider).clear();
      throw Exception('Профиль водителя не найден. Обратитесь к диспетчеру.');
    }
    final api = ref.read(invoApiProvider);
    final p = await api.getDriverProfile();
    state = AsyncData(DriverSession(p));
  }

  Future<void> logout() async {
    await ref.read(invoApiProvider).logout();
    state = const AsyncData(null);
  }
}
