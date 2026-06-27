import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'yandex_order_map_html.dart';

enum YandexOrderMapInteractionMode {
  addressSelection,
  routeDisplayOnly,
}

typedef YandexOrderMapApplyFn = void Function(Map<String, dynamic> payload);
typedef YandexOrderMapResetFn = void Function();
typedef YandexOrderMapCenterFn = void Function(double lat, double lon, {double? zoom});
typedef YandexOrderMapGpsAsPickupFn = void Function(double lat, double lon);
typedef YandexOrderMapSetPointsFn = void Function(
  double pickupLat,
  double pickupLon,
  double dropoffLat,
  double dropoffLon,
);
typedef YandexOrderMapPrefillPickupSilentFn = void Function(String value);
typedef YandexOrderMapBridgeReady = void Function(
  YandexOrderMapApplyFn apply,
  YandexOrderMapResetFn reset,
  YandexOrderMapCenterFn centerMap,
  YandexOrderMapGpsAsPickupFn gpsAsPickup,
  YandexOrderMapSetPointsFn setPoints,
  YandexOrderMapPrefillPickupSilentFn prefillPickupSilent,
);

class YandexOrderMapEmbed extends StatefulWidget {
  const YandexOrderMapEmbed({
    super.key,
    required this.apiKey,
    required this.onPayload,
    required this.onBridgeReady,
    this.visualLightBackground = false,
    this.showAddressSearch = true,
    this.interactionMode = YandexOrderMapInteractionMode.addressSelection,
  });

  final String apiKey;
  final bool visualLightBackground;
  final bool showAddressSearch;
  final YandexOrderMapInteractionMode interactionMode;
  final ValueChanged<Map<String, dynamic>> onPayload;
  final YandexOrderMapBridgeReady onBridgeReady;

  @override
  State<YandexOrderMapEmbed> createState() => _YandexOrderMapEmbedState();
}

class _YandexOrderMapEmbedState extends State<YandexOrderMapEmbed> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(
        yandexOrderMapHtml(
          apiKey: widget.apiKey,
          visualLightBackground: widget.visualLightBackground,
        ),
      );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onBridgeReady(
        widget.onPayload,
        () {},
        (lat, lon, {zoom}) {
          final z = zoom ?? 14;
          _controller.runJavaScript('map && map.setCenter([$lat,$lon], $z);');
        },
        (lat, lon) {},
        (puLat, puLon, drLat, drLon) {
          _controller.runJavaScript('window.setPoints && window.setPoints($puLat,$puLon,$drLat,$drLon);');
        },
        (_) {},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
