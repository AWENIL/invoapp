library invo_common;

const String yandexMapsApiKey = String.fromEnvironment(
  'YANDEX_MAPS_API_KEY',
  defaultValue: '',
);

const String yandexMapsSuggestApiKey = String.fromEnvironment(
  'YANDEX_MAPS_SUGGEST_API_KEY',
  defaultValue: '',
);

class DriverRouteStep {
  const DriverRouteStep({
    required this.instruction,
    required this.distanceM,
    required this.durationSeconds,
    required this.maneuver,
    required this.lat,
    required this.lon,
  });

  final String instruction;
  final double distanceM;
  final int durationSeconds;
  final String maneuver;
  final double lat;
  final double lon;
}

List<List<double>>? parseRoadRoutePoints(Map<String, dynamic>? route) {
  if (route == null) return null;
  final raw = _firstPresent(route, const [
    'road_route_points',
    'route_points',
    'points',
    'polyline',
    'coordinates',
  ]);
  final parsed = _parsePointList(raw);
  if (parsed.isNotEmpty) return parsed;

  final nested = route['route'];
  if (nested is Map) {
    return parseRoadRoutePoints(Map<String, dynamic>.from(nested));
  }
  final geometry = route['geometry'];
  if (geometry is Map) {
    return parseRoadRoutePoints(Map<String, dynamic>.from(geometry));
  }
  return null;
}

List<DriverRouteStep> parseDriverRouteSteps(Map<String, dynamic>? route) {
  if (route == null) return const [];
  final raw = _firstPresent(route, const ['steps', 'maneuvers']);
  if (raw is! List) {
    final nested = route['route'];
    if (nested is Map) {
      return parseDriverRouteSteps(Map<String, dynamic>.from(nested));
    }
    return const [];
  }

  return raw.whereType<Map>().map((item) {
    final step = Map<String, dynamic>.from(item);
    final point = _parsePoint(step['location']) ??
        _parsePoint(step['point']) ??
        _parsePoint(step['position']) ??
        _parsePoint(step);
    if (point == null) return null;
    return DriverRouteStep(
      instruction: _stringValue(step, const ['instruction', 'text', 'name']) ?? '',
      distanceM: _numValue(step, const ['distance_m', 'distance', 'length'])?.toDouble() ?? 0,
      durationSeconds:
          _numValue(step, const ['duration_seconds', 'duration', 'time'])?.round() ?? 0,
      maneuver: _stringValue(step, const ['maneuver', 'type', 'action']) ?? '',
      lat: point[0],
      lon: point[1],
    );
  }).whereType<DriverRouteStep>().toList(growable: false);
}

Object? _firstPresent(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    if (map.containsKey(key)) return map[key];
  }
  return null;
}

String? _stringValue(Map<String, dynamic> map, List<String> keys) {
  final value = _firstPresent(map, keys);
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

num? _numValue(Map<String, dynamic> map, List<String> keys) {
  final value = _firstPresent(map, keys);
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

List<List<double>> _parsePointList(Object? raw) {
  if (raw is! List) return const [];
  final points = <List<double>>[];
  for (final item in raw) {
    final point = _parsePoint(item);
    if (point != null) points.add(point);
  }
  return points;
}

List<double>? _parsePoint(Object? raw) {
  if (raw is List && raw.length >= 2) {
    final a = _toDouble(raw[0]);
    final b = _toDouble(raw[1]);
    if (a == null || b == null) return null;
    if (a.abs() > 90 && b.abs() <= 90) return [b, a];
    return [a, b];
  }
  if (raw is Map) {
    final map = Map<String, dynamic>.from(raw);
    final lat = _numValue(map, const ['lat', 'latitude'])?.toDouble();
    final lon = _numValue(map, const ['lon', 'lng', 'longitude'])?.toDouble();
    if (lat != null && lon != null) return [lat, lon];
  }
  return null;
}

double? _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
