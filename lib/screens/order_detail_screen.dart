import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../order_status_labels.dart';
import '../providers/app_providers.dart';
import '../widgets/arrived_waiting_timer.dart';
import '../widgets/order_route_map.dart';
import '../yandex_maps_links.dart';

final _orderDetailFamily = FutureProvider.family<Map<String, dynamic>, String>((ref, orderId) async {
  return ref.watch(invoApiProvider).getOrder(orderId);
});

Future<Position?> _gpsForOrderRoutes() async {
  try {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition();
  } catch (_) {
    return null;
  }
}

/// Маршрут А→Б, до забора и до высадки (по GPS при наличии).
final _orderMapRoutesFamily =
    FutureProvider.family<({Map<String, dynamic> orderRoute, Map<String, dynamic>? toPickup, Map<String, dynamic>? toDropoff}), String>((ref, orderId) async {
  final api = ref.watch(invoApiProvider);
  final order = await api.getOrder(orderId);
  final status = order['status']?.toString() ?? '';
  final orderRoute = await api.getOrderRoute(orderId);
  final pos = await _gpsForOrderRoutes();
  Map<String, dynamic>? toPickup;
  Map<String, dynamic>? toDropoff;
  if (status == 'assigned' || status == 'driver_en_route') {
    toPickup = await api.getOrderRouteToPickup(
      orderId,
      fromLat: pos?.latitude,
      fromLon: pos?.longitude,
    );
  } else if (status == 'ride_ongoing') {
    toDropoff = await api.getOrderRouteToDropoff(
      orderId,
      fromLat: pos?.latitude,
      fromLon: pos?.longitude,
    );
  }
  return (orderRoute: orderRoute, toPickup: toPickup, toDropoff: toDropoff);
});

bool _pickupLegOnlyStatus(String status) {
  return status == 'assigned' || status == 'driver_en_route';
}

bool _dropoffLegOnlyStatus(String status) {
  return status == 'ride_ongoing';
}

DateTime? _parseArrivedWaitingAt(dynamic v) {
  if (v == null) return null;
  try {
    return DateTime.parse(v.toString()).toLocal();
  } catch (_) {
    return null;
  }
}

String? _nextDriverStatus(String current) {
  const m = {
    'assigned': 'driver_en_route',
    'driver_en_route': 'arrived_waiting',
    'arrived_waiting': 'ride_ongoing',
    'ride_ongoing': 'completed',
  };
  return m[current];
}

String? _formatRouteEta(dynamic eta) {
  if (eta == null) return null;
  try {
    final d = DateTime.parse(eta.toString()).toLocal();
    return DateFormat('dd.MM.yyyy HH:mm').format(d);
  } catch (_) {
    return eta.toString();
  }
}

String? _routeSummaryLine(Map<String, dynamic> route) {
  final parts = <String>[];
  final km = route['distance_km'];
  final min = route['duration_minutes'];
  final eta = route['eta'];
  if (km != null) parts.add('$km км');
  if (min != null) parts.add('$min мин');
  final etaLabel = _formatRouteEta(eta);
  if (etaLabel != null) parts.add('прибытие ~ $etaLabel');
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

String? _driverToPickupSummaryLine(Map<String, dynamic>? route) {
  if (route == null) return null;
  final parts = <String>[];
  final km = route['distance_km'];
  final min = route['duration_minutes'];
  final eta = route['eta'];
  if (km != null) parts.add('$km км');
  if (min != null) parts.add('$min мин');
  final etaLabel = _formatRouteEta(eta);
  if (etaLabel != null) parts.add('к точке А ~ $etaLabel');
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

String? _driverToDropoffSummaryLine(Map<String, dynamic>? route) {
  if (route == null) return null;
  final parts = <String>[];
  final km = route['distance_km'];
  final min = route['duration_minutes'];
  final eta = route['eta'];
  if (km != null) parts.add('$km км');
  if (min != null) parts.add('$min мин');
  final etaLabel = _formatRouteEta(eta);
  if (etaLabel != null) parts.add('к точке Б ~ $etaLabel');
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

bool _statusShowsYandexNav(String status) {
  return status == 'assigned' ||
      status == 'driver_en_route' ||
      status == 'ride_ongoing' ||
      status == 'arrived_waiting';
}

Future<void> _launchYandexDriverNavigation({
  required BuildContext context,
  required String status,
  required double plat,
  required double plon,
  required double dlat,
  required double dlon,
}) async {
  Future<Position?> tryPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  final pos = await tryPosition();
  late final Uri uri;

  if (pos != null) {
    switch (status) {
      case 'assigned':
      case 'driver_en_route':
        uri = yandexMapsRouteBetween(
          fromLat: pos.latitude,
          fromLon: pos.longitude,
          toLat: plat,
          toLon: plon,
        );
        break;
      case 'ride_ongoing':
      case 'arrived_waiting':
        uri = yandexMapsRouteBetween(
          fromLat: pos.latitude,
          fromLon: pos.longitude,
          toLat: dlat,
          toLon: dlon,
        );
        break;
      default:
        return;
    }
  } else {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Геолокация недоступна — маршрут между адресами заказа')),
    );
    uri = yandexMapsRouteBetween(
      fromLat: plat,
      fromLon: plon,
      toLat: dlat,
      toLon: dlon,
    );
  }

  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не удалось открыть Яндекс.Карты')),
    );
  }
}

String _yandexNavLabel(String status) {
  switch (status) {
    case 'assigned':
    case 'driver_en_route':
      return 'Навигация к забору (Яндекс.Карты)';
    case 'ride_ongoing':
      return 'Навигация к высадке (Яндекс.Карты)';
    case 'arrived_waiting':
      return 'Маршрут к высадке (Яндекс.Карты)';
    default:
      return 'Яндекс.Карты';
  }
}

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(_orderDetailFamily(orderId));

    return Scaffold(
      appBar: AppBar(title: Text('Заказ $orderId')),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (order) {
          final status = order['status']?.toString() ?? '';
          final pickup = order['pickup_title']?.toString() ?? '';
          final drop = order['dropoff_title']?.toString() ?? '';
          final plat = (order['pickup_lat'] as num?)?.toDouble();
          final plon = (order['pickup_lon'] as num?)?.toDouble();
          final dlat = (order['dropoff_lat'] as num?)?.toDouble();
          final dlon = (order['dropoff_lon'] as num?)?.toDouble();
          final passenger = order['passenger'];
          String? pName;
          if (passenger is Map) {
            pName = passenger['full_name']?.toString();
          }
          final next = _nextDriverStatus(status);
          final showNav = _statusShowsYandexNav(status);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Статус: ${orderStatusLabelRu(status)}', style: Theme.of(context).textTheme.titleMedium),
                if (pName != null) Text('Пассажир: $pName'),
                const SizedBox(height: 8),
                Text('Откуда: $pickup'),
                Text('Куда: $drop'),
                if (status == 'arrived_waiting') ...[
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final at = _parseArrivedWaitingAt(order['arrived_waiting_at']);
                      if (at != null) {
                        return ArrivedWaitingTimer(arrivedWaitingAt: at);
                      }
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            'Ожидание пассажира (20 мин). Время начала появится после обновления сервера.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 16),
                if (plat != null && plon != null && dlat != null && dlon != null) ...[
                  ref.watch(_orderMapRoutesFamily(orderId)).when(
                        loading: () => const LinearProgressIndicator(),
                        error: (_, _) => OrderRouteMap(
                          pickupLat: plat,
                          pickupLon: plon,
                          dropLat: dlat,
                          dropLon: dlon,
                          pointAAddress: pickup,
                          pointBAddress: drop,
                          pickupLegOnly: _pickupLegOnlyStatus(status),
                          dropoffLegOnly: _dropoffLegOnlyStatus(status),
                        ),
                        data: (data) {
                          final points = parseRoadRoutePoints(data.orderRoute);
                          final toPickupPts = parseRoadRoutePoints(data.toPickup);
                          final toDropoffPts = parseRoadRoutePoints(data.toDropoff);
                          final summary = _routeSummaryLine(data.orderRoute);
                          final legPickup = _driverToPickupSummaryLine(data.toPickup);
                          final legDrop = _driverToDropoffSummaryLine(data.toDropoff);
                          return OrderRouteMap(
                            pickupLat: plat,
                            pickupLon: plon,
                            dropLat: dlat,
                            dropLon: dlon,
                            pointAAddress: pickup,
                            pointBAddress: drop,
                            roadRoutePoints: points,
                            driverToPickupPoints: toPickupPts,
                            driverToDropoffPoints: toDropoffPts,
                            routeSummary: summary,
                            driverToPickupSummary: legPickup,
                            driverToDropoffSummary: legDrop,
                            pickupLegOnly: _pickupLegOnlyStatus(status),
                            dropoffLegOnly: _dropoffLegOnlyStatus(status),
                          );
                        },
                      ),
                  if (showNav) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => _launchYandexDriverNavigation(
                        context: context,
                        status: status,
                        plat: plat,
                        plon: plon,
                        dlat: dlat,
                        dlon: dlon,
                      ),
                      icon: const Icon(Icons.navigation),
                      label: Text(_yandexNavLabel(status)),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
                if (next != null)
                  FilledButton(
                    onPressed: () async {
                      try {
                        await ref.read(invoApiProvider).patchOrderStatus(
                              orderId,
                              next,
                              reason: _defaultReason(next),
                            );
                        ref.invalidate(_orderDetailFamily(orderId));
                        ref.invalidate(_orderMapRoutesFamily(orderId));
                        ref.invalidate(driverOrdersProvider);
                        ref.invalidate(driverActiveOrderProvider);
                        if (context.mounted &&
                            next != 'driver_en_route' &&
                            next != 'arrived_waiting' &&
                            next != 'ride_ongoing') {
                          Navigator.of(context).pop();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                    child: Text(_actionLabel(next)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _actionLabel(String next) {
    switch (next) {
      case 'driver_en_route':
        return 'Выехал к пассажиру';
      case 'arrived_waiting':
        return 'Прибыл, жду';
      case 'ride_ongoing':
        return 'Начать поездку';
      case 'completed':
        return 'Завершить поездку';
      default:
        return 'Далее';
    }
  }

  String _defaultReason(String next) {
    switch (next) {
      case 'driver_en_route':
        return 'В пути к точке забора';
      case 'arrived_waiting':
        return 'Прибыл';
      case 'ride_ongoing':
        return 'Поездка началась';
      case 'completed':
        return 'Завершено';
      default:
        return '';
    }
  }
}
