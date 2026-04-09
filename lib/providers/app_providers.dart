import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/invo_api.dart';
import '../services/token_storage.dart';

final driverOrdersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final raw = await ref.watch(invoApiProvider).getOrders();
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

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final invoApiProvider = Provider<InvoApi>((ref) {
  final t = ref.watch(tokenStorageProvider);
  return InvoApi(t);
});

class DriverSession {
  DriverSession(this.profile);
  final Map<String, dynamic> profile;

  String get name => (profile['name'] ?? '') as String? ?? 'Водитель';
  bool get isOnline => profile['is_online'] == true;
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
