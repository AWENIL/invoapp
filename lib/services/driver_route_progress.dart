import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:invo_common/invo_common.dart';

class DriverNavSnapshot {
  const DriverNavSnapshot({
    required this.nextStep,
    required this.distanceToManeuverM,
    required this.remainingDistanceM,
    required this.remainingDurationSeconds,
    required this.offRoute,
    required this.polylineIndex,
  });

  final DriverRouteStep? nextStep;
  final double distanceToManeuverM;
  final double remainingDistanceM;
  final int remainingDurationSeconds;
  final bool offRoute;
  final int polylineIndex;

  String get maneuverBanner {
    final step = nextStep;
    if (step == null) return 'Продолжайте движение';
    if (distanceToManeuverM >= 1000) {
      return 'Через ${(distanceToManeuverM / 1000).toStringAsFixed(1)} км · ${step.instruction}';
    }
    if (distanceToManeuverM >= 50) {
      return 'Через ${distanceToManeuverM.round()} м · ${step.instruction}';
    }
    return step.instruction;
  }
}

class DriverRouteProgressTracker {
  DriverRouteProgressTracker({
    required List<List<double>> polyline,
    required List<DriverRouteStep> steps,
    required int totalDurationSeconds,
    required double totalDistanceM,
  })  : _polyline = polyline,
        _steps = steps,
        _totalDurationSeconds = totalDurationSeconds,
        _totalDistanceM = totalDistanceM;

  final List<List<double>> _polyline;
  final List<DriverRouteStep> _steps;
  final int _totalDurationSeconds;
  final double _totalDistanceM;

  static const offRouteThresholdM = 80.0;

  DriverNavSnapshot update(double lat, double lon) {
    if (_polyline.length < 2) {
      return const DriverNavSnapshot(
        nextStep: null,
        distanceToManeuverM: 0,
        remainingDistanceM: 0,
        remainingDurationSeconds: 0,
        offRoute: false,
        polylineIndex: 0,
      );
    }

    final idx = _nearestPolylineIndex(lat, lon);
    final offRoute = _distanceToPolylineAt(lat, lon, idx) > offRouteThresholdM;
    final remainingM = _remainingDistanceFromIndex(idx, lat, lon);
    final progress = _totalDistanceM <= 0 ? 0.0 : (1 - (remainingM / _totalDistanceM)).clamp(0.0, 1.0);
    final remainingSec = (_totalDurationSeconds * (1 - progress)).round().clamp(0, _totalDurationSeconds);

    final next = _nextStepAfterIndex(idx, lat, lon);
    return DriverNavSnapshot(
      nextStep: next.step,
      distanceToManeuverM: next.distanceM,
      remainingDistanceM: remainingM,
      remainingDurationSeconds: remainingSec,
      offRoute: offRoute,
      polylineIndex: idx,
    );
  }

  int _nearestPolylineIndex(double lat, double lon) {
    var bestIdx = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < _polyline.length; i++) {
      final p = _polyline[i];
      final d = Geolocator.distanceBetween(lat, lon, p[0], p[1]);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  double _distanceToPolylineAt(double lat, double lon, int idx) {
    final p = _polyline[idx];
    return Geolocator.distanceBetween(lat, lon, p[0], p[1]);
  }

  double _remainingDistanceFromIndex(int idx, double lat, double lon) {
    var total = Geolocator.distanceBetween(
      lat,
      lon,
      _polyline[idx][0],
      _polyline[idx][1],
    );
    for (var i = idx; i < _polyline.length - 1; i++) {
      total += Geolocator.distanceBetween(
        _polyline[i][0],
        _polyline[i][1],
        _polyline[i + 1][0],
        _polyline[i + 1][1],
      );
    }
    return total;
  }

  double _polylineDistanceBetweenIndices(int fromIdx, int toIdx) {
    if (toIdx <= fromIdx) return 0;
    var total = 0.0;
    for (var i = fromIdx; i < toIdx; i++) {
      total += Geolocator.distanceBetween(
        _polyline[i][0],
        _polyline[i][1],
        _polyline[i + 1][0],
        _polyline[i + 1][1],
      );
    }
    return total;
  }

  int _stepPolylineIndex(DriverRouteStep step) {
    return _nearestPolylineIndex(step.lat, step.lon);
  }

  ({DriverRouteStep? step, double distanceM}) _nextStepAfterIndex(int idx, double lat, double lon) {
    DriverRouteStep? candidate;
    var bestDist = double.infinity;
    for (final step in _steps) {
      if (step.maneuver == 'arrive' || step.maneuver == 'depart') continue;
      final stepIdx = _stepPolylineIndex(step);
      if (stepIdx <= idx) continue;
      final dist = _polylineDistanceBetweenIndices(idx, stepIdx) +
          Geolocator.distanceBetween(lat, lon, _polyline[idx][0], _polyline[idx][1]);
      if (dist < bestDist) {
        bestDist = dist;
        candidate = step;
      }
    }
    if (candidate == null) {
      for (final step in _steps) {
        if (step.maneuver != 'arrive') continue;
        candidate = step;
        bestDist = _remainingDistanceFromIndex(idx, lat, lon);
        break;
      }
    }
    return (step: candidate, distanceM: bestDist.isFinite ? bestDist : 0);
  }
}

IconData maneuverIcon(String maneuver) {
  final m = maneuver.toLowerCase();
  if (m.contains('uturn') || m.contains('u-turn')) return Icons.u_turn_left;
  if (m.contains('left')) return Icons.turn_left;
  if (m.contains('right')) return Icons.turn_right;
  if (m.contains('roundabout') || m.contains('rotary')) return Icons.roundabout_left;
  if (m.contains('arrive')) return Icons.flag_outlined;
  if (m.contains('depart')) return Icons.navigation_outlined;
  return Icons.straight;
}

String formatRemainingDistance(double meters) {
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(1)} км';
  }
  return '${meters.round()} м';
}

String formatEtaTime(DateTime eta) {
  final h = eta.hour.toString().padLeft(2, '0');
  final m = eta.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

double parseRouteDistanceM(Map<String, dynamic> route) {
  final dm = route['distance_m'];
  if (dm is num) return dm.toDouble();
  final km = route['distance_km'];
  if (km is num) return km.toDouble() * 1000;
  return 0;
}

int parseRouteDurationSeconds(Map<String, dynamic> route) {
  final sec = route['duration_seconds'];
  if (sec is num) return sec.round();
  final min = route['duration_minutes'];
  if (min is num) return (min * 60).round();
  return 0;
}
