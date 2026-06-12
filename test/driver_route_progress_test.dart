import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invo_common/invo_common.dart';
import 'package:invo_driver/services/driver_route_progress.dart';

void main() {
  group('parseDriverRouteSteps', () {
    test('parses steps from API payload', () {
      final steps = parseDriverRouteSteps({
        'steps': [
          {
            'instruction': 'Поверните направо',
            'distance_m': 200,
            'duration_seconds': 30,
            'maneuver': 'turn-right',
            'location': [51.17, 71.44],
          },
        ],
      });
      expect(steps.length, 1);
      expect(steps.first.instruction, 'Поверните направо');
      expect(steps.first.lat, 51.17);
      expect(steps.first.lon, 71.44);
    });
  });

  group('DriverRouteProgressTracker', () {
    test('returns next step ahead on polyline', () {
      final tracker = DriverRouteProgressTracker(
        polyline: [
          [51.1700, 71.4400],
          [51.1705, 71.4405],
          [51.1710, 71.4410],
          [51.1715, 71.4415],
        ],
        steps: [
          const DriverRouteStep(
            instruction: 'Начните движение',
            distanceM: 100,
            durationSeconds: 20,
            maneuver: 'depart',
            lat: 51.1700,
            lon: 71.4400,
          ),
          const DriverRouteStep(
            instruction: 'Поверните направо',
            distanceM: 150,
            durationSeconds: 25,
            maneuver: 'turn-right',
            lat: 51.1710,
            lon: 71.4410,
          ),
          const DriverRouteStep(
            instruction: 'Вы прибыли',
            distanceM: 0,
            durationSeconds: 0,
            maneuver: 'arrive',
            lat: 51.1715,
            lon: 71.4415,
          ),
        ],
        totalDurationSeconds: 120,
        totalDistanceM: 500,
      );

      final snap = tracker.update(51.1701, 71.4401);
      expect(snap.nextStep?.maneuver, 'turn-right');
      expect(snap.remainingDistanceM, greaterThan(0));
      expect(snap.offRoute, isFalse);
    });

    test('detects off-route when far from polyline', () {
      final tracker = DriverRouteProgressTracker(
        polyline: [
          [51.1700, 71.4400],
          [51.1710, 71.4410],
        ],
        steps: const [],
        totalDurationSeconds: 60,
        totalDistanceM: 1000,
      );

      final snap = tracker.update(51.2000, 71.5000);
      expect(snap.offRoute, isTrue);
    });

    test('maneuverBanner formats distance prefix', () {
      const snap = DriverNavSnapshot(
        nextStep: DriverRouteStep(
          instruction: 'Поверните направo',
          distanceM: 320,
          durationSeconds: 40,
          maneuver: 'turn-right',
          lat: 51.17,
          lon: 71.44,
        ),
        distanceToManeuverM: 250,
        remainingDistanceM: 900,
        remainingDurationSeconds: 120,
        offRoute: false,
        polylineIndex: 1,
      );
      expect(snap.maneuverBanner, contains('250 м'));
      expect(snap.maneuverBanner, contains('Поверните'));
    });
  });
}
