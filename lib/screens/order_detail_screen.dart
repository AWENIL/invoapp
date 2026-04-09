import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../widgets/order_route_map.dart';

final _orderDetailFamily = FutureProvider.family<Map<String, dynamic>, String>((ref, orderId) async {
  return ref.watch(invoApiProvider).getOrder(orderId);
});

final _orderRouteFamily = FutureProvider.family<Map<String, dynamic>, String>((ref, orderId) async {
  return ref.watch(invoApiProvider).getOrderRoute(orderId);
});

String? _nextDriverStatus(String current) {
  const m = {
    'assigned': 'driver_en_route',
    'driver_en_route': 'arrived_waiting',
    'arrived_waiting': 'ride_ongoing',
    'ride_ongoing': 'completed',
  };
  return m[current];
}

String _statusLabel(String code) {
  const labels = {
    'assigned': 'Назначен',
    'driver_en_route': 'Еду к пассажиру',
    'arrived_waiting': 'Ожидаю',
    'ride_ongoing': 'В пути',
    'completed': 'Завершён',
    'cancelled': 'Отменён',
    'offered': 'Предложен',
    'matching': 'Подбор',
    'active_queue': 'В очереди',
  };
  return labels[code] ?? code;
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Статус: ${_statusLabel(status)}', style: Theme.of(context).textTheme.titleMedium),
                if (pName != null) Text('Пассажир: $pName'),
                const SizedBox(height: 8),
                Text('Откуда: $pickup'),
                Text('Куда: $drop'),
                const SizedBox(height: 16),
                if (plat != null && plon != null && dlat != null && dlon != null) ...[
                  ref.watch(_orderRouteFamily(orderId)).when(
                        loading: () => const LinearProgressIndicator(),
                        error: (_, stack) => OrderRouteMap(
                          pickupLat: plat,
                          pickupLon: plon,
                          dropLat: dlat,
                          dropLon: dlon,
                        ),
                        data: (route) {
                          final poly = route['polyline']?.toString();
                          return OrderRouteMap(
                            pickupLat: plat,
                            pickupLon: plon,
                            dropLat: dlat,
                            dropLon: dlon,
                            polylineEncoded: poly,
                          );
                        },
                      ),
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
                        ref.invalidate(driverOrdersProvider);
                        if (context.mounted) Navigator.of(context).pop();
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
