import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Разовое получение координат после входа. Без исключений наружу.
abstract final class DriverLocationSync {
  /// До любых экранов входа: запрос разрешения и (по возможности) одно считывание координат —
  /// на мобильных показывает системный диалог, в браузере — запрос геолокации у сайта.
  ///
  /// После ответа пользователя не ждём первый fix GPS — иначе веб/эмулятор «висят» на
  /// [getCurrentPosition]. Координаты догружаются в фоне.
  static Future<void> primeLocationAtStartup() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      if (!kIsWeb) {
        final serviceOn = await Geolocator.isLocationServiceEnabled();
        if (!serviceOn) return;
      }
      unawaited(_warmPositionInBackground());
    } catch (_) {}
  }

  /// Один запрос координат с ограничением по времени (не блокировать экраны надолго).
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
      if (!kIsWeb) {
        final serviceOn = await Geolocator.isLocationServiceEnabled();
        if (!serviceOn) return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: kIsWeb ? LocationAccuracy.low : LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 12),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _warmPositionInBackground() async {
    try {
      await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: kIsWeb ? LocationAccuracy.low : LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 20),
        ),
      );
    } catch (_) {}
  }
}
