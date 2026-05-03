import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Разовое получение координат после входа. Без исключений наружу.
abstract final class DriverLocationSync {
  /// До любых экранов входа: запрос разрешения и (по возможности) одно считывание координат —
  /// на мобильных показывает системный диалог, в браузере — запрос геолокации у сайта.
  static Future<void> primeLocationAtStartup() async {
    await getCurrentPositionOrNull();
  }

  static Future<Position?> getCurrentPositionOrNull() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      // На Web нет «службы геолокации» в смысле Android — иначе часто получаем ложный false.
      if (!kIsWeb) {
        final serviceOn = await Geolocator.isLocationServiceEnabled();
        if (!serviceOn) return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
