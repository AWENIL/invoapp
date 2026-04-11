import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Парсит поле `route` из ответа API маршрута заказа: `[[lat, lon], ...]`.
List<LatLng>? parseRoadRoutePoints(Map<String, dynamic>? route) {
  if (route == null) return null;
  final raw = route['route'];
  if (raw is! List) return null;
  final out = <LatLng>[];
  for (final e in raw) {
    if (e is List && e.length >= 2) {
      final a = e[0];
      final b = e[1];
      if (a is num && b is num) {
        out.add(LatLng(a.toDouble(), b.toDouble()));
      }
    }
  }
  return out.isEmpty ? null : out;
}

String formatLatLonLine(double lat, double lon) {
  return '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';
}

bool _latLngListsEqual(List<LatLng>? a, List<LatLng>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) return false;
  }
  return true;
}

/// Карта: WebView Яндекс на iOS/Android; OSM на остальных.
/// [pickupLegOnly] — только путь к точке А; [dropoffLegOnly] — только к точке Б (поездка).
class OrderRouteMap extends StatefulWidget {
  const OrderRouteMap({
    super.key,
    required this.pickupLat,
    required this.pickupLon,
    required this.dropLat,
    required this.dropLon,
    this.pointAAddress = '',
    this.pointBAddress = '',
    this.roadRoutePoints,
    this.driverToPickupPoints,
    this.driverToDropoffPoints,
    this.routeSummary,
    this.driverToPickupSummary,
    this.driverToDropoffSummary,
    this.pickupLegOnly = false,
    this.dropoffLegOnly = false,
  });

  final double pickupLat;
  final double pickupLon;
  final double dropLat;
  final double dropLon;
  final String pointAAddress;
  final String pointBAddress;
  final List<LatLng>? roadRoutePoints;
  final List<LatLng>? driverToPickupPoints;
  final List<LatLng>? driverToDropoffPoints;
  final String? routeSummary;
  final String? driverToPickupSummary;
  final String? driverToDropoffSummary;
  final bool pickupLegOnly;
  final bool dropoffLegOnly;

  @override
  State<OrderRouteMap> createState() => _OrderRouteMapState();
}

class _OrderRouteMapState extends State<OrderRouteMap> {
  WebViewController? _web;
  static const double _mapHeight = 300;

  static const Color _orderRouteBlue = Color(0xFF1565C0);
  static const Color _driverLegBlue = Color(0xFF42A5F5);

  bool _useYandexWebView() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Uri _yandexRouteUri() {
    final drvPickup = widget.driverToPickupPoints;
    final drvDrop = widget.driverToDropoffPoints;

    if (widget.dropoffLegOnly) {
      if (drvDrop != null && drvDrop.length >= 2) {
        final start = drvDrop.first;
        return Uri.parse(
          'https://yandex.ru/maps/?mode=routes&rtext=${start.latitude},${start.longitude}~${widget.dropLat},${widget.dropLon}',
        );
      }
      return Uri.parse(
        'https://yandex.ru/maps/?mode=routes&rtext=${widget.pickupLat},${widget.pickupLon}~${widget.dropLat},${widget.dropLon}',
      );
    }

    if (widget.pickupLegOnly) {
      if (drvPickup != null && drvPickup.length >= 2) {
        final start = drvPickup.first;
        return Uri.parse(
          'https://yandex.ru/maps/?mode=routes&rtext=${start.latitude},${start.longitude}~${widget.pickupLat},${widget.pickupLon}',
        );
      }
      return Uri.parse(
        'https://yandex.ru/maps/?mode=routes&rtext=${widget.pickupLat},${widget.pickupLon}~${widget.dropLat},${widget.dropLon}',
      );
    }

    if (drvPickup != null && drvPickup.length >= 2) {
      final start = drvPickup.first;
      return Uri.parse(
        'https://yandex.ru/maps/?mode=routes&rtext=${start.latitude},${start.longitude}~${widget.pickupLat},${widget.pickupLon}~${widget.dropLat},${widget.dropLon}',
      );
    }
    return Uri.parse(
      'https://yandex.ru/maps/?mode=routes&rtext=${widget.pickupLat},${widget.pickupLon}~${widget.dropLat},${widget.dropLon}',
    );
  }

  @override
  void initState() {
    super.initState();
    if (_useYandexWebView()) {
      final uri = _yandexRouteUri();
      _web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(uri);
    }
  }

  @override
  void didUpdateWidget(OrderRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_web == null) return;
    final coordsChanged = oldWidget.pickupLat != widget.pickupLat ||
        oldWidget.pickupLon != widget.pickupLon ||
        oldWidget.dropLat != widget.dropLat ||
        oldWidget.dropLon != widget.dropLon;
    final pickupDrvChanged =
        !_latLngListsEqual(oldWidget.driverToPickupPoints, widget.driverToPickupPoints);
    final dropDrvChanged =
        !_latLngListsEqual(oldWidget.driverToDropoffPoints, widget.driverToDropoffPoints);
    final modeChanged = oldWidget.pickupLegOnly != widget.pickupLegOnly ||
        oldWidget.dropoffLegOnly != widget.dropoffLegOnly;
    if (coordsChanged || pickupDrvChanged || dropDrvChanged || modeChanged) {
      _web!.loadRequest(_yandexRouteUri());
    }
  }

  Future<void> _openYandexExternally() async {
    await launchUrl(_yandexRouteUri(), mode: LaunchMode.externalApplication);
  }

  Widget _addressHeaderBlock(BuildContext context) {
    final theme = Theme.of(context);
    final aAddr = widget.pointAAddress.trim();
    final bAddr = widget.pointBAddress.trim();
    final aCoord = formatLatLonLine(widget.pickupLat, widget.pickupLon);
    final bCoord = formatLatLonLine(widget.dropLat, widget.dropLon);
    final aText = aAddr.isEmpty ? aCoord : '$aAddr ($aCoord)';
    final bText = bAddr.isEmpty ? bCoord : '$bAddr ($bCoord)';

    if (widget.dropoffLegOnly) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Навигация к точке завершения (Б)',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  const TextSpan(text: 'Точка Б: ', style: TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: bText),
                ],
              ),
            ),
            if (widget.routeSummary != null && widget.routeSummary!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Маршрут заказа (А → Б): ${widget.routeSummary}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      );
    }

    if (widget.pickupLegOnly) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Маршрут к точке забора',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  const TextSpan(text: 'Точка А: ', style: TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: aText),
                ],
              ),
            ),
            if (widget.routeSummary != null && widget.routeSummary!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Далее по заказу (А → Б): ${widget.routeSummary}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Полный маршрут от точки А до точки Б',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                const TextSpan(text: 'А: ', style: TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: aText),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                const TextSpan(text: 'Б: ', style: TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: bText),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<LatLng> _pointsForCamera(
    List<LatLng> orderPts,
    List<LatLng>? toPickup,
    List<LatLng>? toDropoff,
    bool pickupLeg,
    bool dropoffLeg,
  ) {
    if (dropoffLeg) {
      if (toDropoff != null && toDropoff.length >= 2) {
        return List<LatLng>.from(toDropoff);
      }
      return <LatLng>[orderPts.last];
    }
    if (pickupLeg) {
      if (toPickup != null && toPickup.length >= 2) {
        return List<LatLng>.from(toPickup);
      }
      return <LatLng>[orderPts.first];
    }
    final out = <LatLng>[];
    if (toPickup != null && toPickup.length >= 2) {
      out.addAll(toPickup);
    }
    out.addAll(orderPts);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pickupLeg = widget.pickupLegOnly;
    final dropoffLeg = widget.dropoffLegOnly;

    if (_web != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _addressHeaderBlock(context),
          if (dropoffLeg &&
              widget.driverToDropoffSummary != null &&
              widget.driverToDropoffSummary!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Путь к высадке: ${widget.driverToDropoffSummary}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          if (!dropoffLeg &&
              widget.driverToPickupSummary != null &&
              widget.driverToPickupSummary!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Ваш путь к точке А: ${widget.driverToPickupSummary}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          if (!pickupLeg &&
              !dropoffLeg &&
              widget.routeSummary != null &&
              widget.routeSummary!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Маршрут А → Б: ${widget.routeSummary}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          if (pickupLeg &&
              widget.routeSummary != null &&
              widget.routeSummary!.isNotEmpty &&
              !dropoffLeg)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Маршрут А → Б: ${widget.routeSummary}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          SizedBox(
            height: _mapHeight,
            child: WebViewWidget(controller: _web!),
          ),
          TextButton.icon(
            onPressed: _openYandexExternally,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Открыть в приложении карт'),
          ),
        ],
      );
    }

    final pickup = LatLng(widget.pickupLat, widget.pickupLon);
    final drop = LatLng(widget.dropLat, widget.dropLon);
    final orderPts = (widget.roadRoutePoints != null && widget.roadRoutePoints!.length >= 2)
        ? widget.roadRoutePoints!
        : <LatLng>[pickup, drop];

    final toPickup = widget.driverToPickupPoints;
    final toDrop = widget.driverToDropoffPoints;

    final fitPts = _pointsForCamera(orderPts, toPickup, toDrop, pickupLeg, dropoffLeg);

    final polylines = <Polyline>[];
    if (dropoffLeg) {
      if (toDrop != null && toDrop.length >= 2) {
        polylines.add(
          Polyline(points: toDrop, strokeWidth: 5, color: _orderRouteBlue),
        );
      }
    } else if (pickupLeg) {
      if (toPickup != null && toPickup.length >= 2) {
        polylines.add(
          Polyline(points: toPickup, strokeWidth: 4, color: _orderRouteBlue),
        );
      }
    } else {
      if (toPickup != null && toPickup.length >= 2) {
        polylines.add(
          Polyline(points: toPickup, strokeWidth: 4, color: _driverLegBlue),
        );
      }
      polylines.add(
        Polyline(points: orderPts, strokeWidth: 4, color: _orderRouteBlue),
      );
    }

    final markers = <Marker>[];
    if (dropoffLeg) {
      if (toDrop != null && toDrop.length >= 2) {
        markers.add(
          Marker(
            point: toDrop.first,
            width: 34,
            height: 34,
            child: Icon(Icons.my_location, color: _orderRouteBlue, shadows: [
              Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 2),
            ]),
          ),
        );
      }
      markers.add(
        Marker(
          point: orderPts.last,
          width: 36,
          height: 36,
          child: const Icon(Icons.flag, color: Colors.red),
        ),
      );
    } else if (pickupLeg) {
      if (toPickup != null && toPickup.length >= 2) {
        markers.add(
          Marker(
            point: toPickup.first,
            width: 34,
            height: 34,
            child: Icon(Icons.my_location, color: _orderRouteBlue, shadows: [
              Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 2),
            ]),
          ),
        );
      }
      markers.add(
        Marker(
          point: orderPts.first,
          width: 32,
          height: 32,
          child: const Icon(Icons.taxi_alert, color: Colors.green),
        ),
      );
    } else {
      if (toPickup != null && toPickup.length >= 2) {
        markers.add(
          Marker(
            point: toPickup.first,
            width: 34,
            height: 34,
            child: Icon(Icons.my_location, color: _driverLegBlue, shadows: [
              Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 2),
            ]),
          ),
        );
      }
      markers.add(
        Marker(
          point: orderPts.first,
          width: 32,
          height: 32,
          child: const Icon(Icons.taxi_alert, color: Colors.green),
        ),
      );
      markers.add(
        Marker(
          point: orderPts.last,
          width: 32,
          height: 32,
          child: const Icon(Icons.flag, color: Colors.red),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _addressHeaderBlock(context),
        if (dropoffLeg &&
            widget.driverToDropoffSummary != null &&
            widget.driverToDropoffSummary!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Путь к высадке: ${widget.driverToDropoffSummary}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        if (!dropoffLeg &&
            widget.driverToPickupSummary != null &&
            widget.driverToPickupSummary!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Ваш путь к точке А: ${widget.driverToPickupSummary}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        if (!pickupLeg && !dropoffLeg && widget.routeSummary != null && widget.routeSummary!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Маршрут А → Б: ${widget.routeSummary}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        if (pickupLeg &&
            widget.routeSummary != null &&
            widget.routeSummary!.isNotEmpty &&
            !dropoffLeg)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Маршрут А → Б: ${widget.routeSummary}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        SizedBox(
          height: _mapHeight,
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: fitPts.length >= 2
                  ? CameraFit.coordinates(
                      coordinates: fitPts,
                      padding: const EdgeInsets.all(24),
                      maxZoom: 18,
                    )
                  : null,
              initialCenter: fitPts.isNotEmpty ? fitPts.first : pickup,
              initialZoom: 12,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.invotaxi.invo_driver',
              ),
              PolylineLayer(polylines: polylines),
              MarkerLayer(markers: markers),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: _openYandexExternally,
          icon: const Icon(Icons.navigation_outlined),
          label: const Text('Яндекс.Карты'),
        ),
      ],
    );
  }
}
