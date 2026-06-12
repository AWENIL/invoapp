import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class DriverNavigationPosition {
  const DriverNavigationPosition({
    required this.lat,
    required this.lon,
    required this.heading,
    required this.position,
  });

  final double lat;
  final double lon;
  final double heading;
  final Position position;
}

/// Поток GPS для экрана навигации с throttled PATCH на сервер.
class DriverNavigationLocationService {
  StreamSubscription<Position>? _sub;
  Position? _prevPosition;
  DateTime? _lastBackendPatchAt;
  ({double lat, double lon})? _lastPatchedCoords;

  static const _backendMinInterval = Duration(seconds: 9);
  static const _backendMinMoveM = 30.0;

  Future<bool> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }
    if (!kIsWeb) {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) return false;
    }
    return true;
  }

  void start({
    required void Function(DriverNavigationPosition update) onUpdate,
    required Future<void> Function(double lat, double lon) onBackendPatch,
  }) {
    stop();
    _sub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: kIsWeb ? LocationAccuracy.medium : LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      final heading = _headingFrom(pos);
      onUpdate(
        DriverNavigationPosition(
          lat: pos.latitude,
          lon: pos.longitude,
          heading: heading,
          position: pos,
        ),
      );
      unawaited(_maybePatchBackend(pos, onBackendPatch));
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _prevPosition = null;
    _lastBackendPatchAt = null;
    _lastPatchedCoords = null;
  }

  double _headingFrom(Position pos) {
    if (pos.heading >= 0 && pos.heading <= 360) {
      return pos.heading;
    }
    final prev = _prevPosition;
    _prevPosition = pos;
    if (prev == null) return 0;
    return Geolocator.bearingBetween(
      prev.latitude,
      prev.longitude,
      pos.latitude,
      pos.longitude,
    );
  }

  Future<void> _maybePatchBackend(
    Position pos,
    Future<void> Function(double lat, double lon) onBackendPatch,
  ) async {
    final now = DateTime.now();
    final lastAt = _lastBackendPatchAt;
    final lastCoords = _lastPatchedCoords;
    if (lastAt != null && now.difference(lastAt) < _backendMinInterval) {
      if (lastCoords != null) {
        final moved = Geolocator.distanceBetween(
          lastCoords.lat,
          lastCoords.lon,
          pos.latitude,
          pos.longitude,
        );
        if (moved < _backendMinMoveM) return;
      } else {
        return;
      }
    }
    _lastBackendPatchAt = now;
    _lastPatchedCoords = (lat: pos.latitude, lon: pos.longitude);
    try {
      await onBackendPatch(pos.latitude, pos.longitude);
    } catch (_) {}
  }
}
