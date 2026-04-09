import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Карта маршрута: на мобильных — Яндекс в WebView; на web — OSM + полилиния (упрощённо).
class OrderRouteMap extends StatefulWidget {
  const OrderRouteMap({
    super.key,
    required this.pickupLat,
    required this.pickupLon,
    required this.dropLat,
    required this.dropLon,
    this.polylineEncoded,
  });

  final double pickupLat;
  final double pickupLon;
  final double dropLat;
  final double dropLon;
  final String? polylineEncoded;

  @override
  State<OrderRouteMap> createState() => _OrderRouteMapState();
}

class _OrderRouteMapState extends State<OrderRouteMap> {
  WebViewController? _web;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final uri = Uri.parse(
        'https://yandex.ru/maps/?mode=routes&rtext=${widget.pickupLat},${widget.pickupLon}~${widget.dropLat},${widget.dropLon}',
      );
      _web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(uri);
    }
  }

  Future<void> _openYandexApp() async {
    final u = Uri.parse(
      'https://yandex.ru/maps/?mode=routes&rtext=${widget.pickupLat},${widget.pickupLon}~${widget.dropLat},${widget.dropLon}',
    );
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_web != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: WebViewWidget(controller: _web!),
          ),
          TextButton.icon(
            onPressed: _openYandexApp,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Открыть в приложении карт'),
          ),
        ],
      );
    }

    final points = <LatLng>[
      LatLng(widget.pickupLat, widget.pickupLon),
      LatLng(widget.dropLat, widget.dropLon),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: points.first,
              initialZoom: 12,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.invotaxi.invo_driver',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(points: points, strokeWidth: 4, color: Colors.amber),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: points.first,
                    width: 32,
                    height: 32,
                    child: const Icon(Icons.taxi_alert, color: Colors.green),
                  ),
                  Marker(
                    point: points.last,
                    width: 32,
                    height: 32,
                    child: const Icon(Icons.flag, color: Colors.red),
                  ),
                ],
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: _openYandexApp,
          icon: const Icon(Icons.navigation_outlined),
          label: const Text('Яндекс.Карты'),
        ),
      ],
    );
  }
}
