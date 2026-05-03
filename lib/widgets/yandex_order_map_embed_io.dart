import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'yandex_order_map_html.dart';

/// Яндекс.Карта в WebView (iOS, Android, десктоп с нативным WebView).
class YandexOrderMapEmbed extends StatefulWidget {
  const YandexOrderMapEmbed({
    super.key,
    required this.apiKey,
    this.clean = false,
    this.visualLightBackground = false,
    this.showAddressSearch = false,
    this.interactionMode = YandexOrderMapInteractionMode.both,
    required this.onPayload,
    required this.onBridgeReady,
  });

  final String apiKey;

  /// Если true — карта только фон: жесты проходят к Flutter-слоям поверх (bottom sheet и т.п.).
  final bool clean;

  /// Светлая подложка и упрощённый HTML (главная под bottom sheet).
  final bool visualLightBackground;

  final bool showAddressSearch;

  final YandexOrderMapInteractionMode interactionMode;
  final void Function(String rawJsonPayload) onPayload;
  final void Function(
    Future<void> Function() apply,
    Future<void> Function() reset,
    Future<void> Function(double lat, double lon, {int? zoom}) centerMap,
    Future<void> Function(double lat, double lon) gpsAsPickup,
    Future<void> Function(double puLat, double puLon, double drLat, double drLon) setPoints,
    Future<void> Function(double lat, double lon) prefillPickupSilent,
  ) onBridgeReady;

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
      ..setBackgroundColor(
        widget.visualLightBackground ? const Color(0xFFF8F0EC) : const Color(0xFF121218),
      )
      ..addJavaScriptChannel(
        'InvoYandexMap',
        onMessageReceived: (JavaScriptMessage message) {
          widget.onPayload(message.message);
        },
      )
      ..loadHtmlString(
        buildYandexOrderMapHtml(
          apiKey: widget.apiKey,
          bridgeScript: yandexMapBridgeWebView,
          visualLightBackground: widget.visualLightBackground,
          showAddressSearch: widget.showAddressSearch,
          interactionMode: widget.interactionMode,
        ),
        baseUrl: 'https://yandex.ru',
      );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onBridgeReady(
        () => _controller.runJavaScript('applyToFlutter()'),
        () => _controller.runJavaScript('resetPoints()'),
        (double lat, double lon, {int? zoom}) => _controller.runJavaScript(
          'centerFromFlutter($lat,$lon,${zoom ?? 14})',
        ),
        (double lat, double lon) => _controller.runJavaScript(
          'applyGpsAsPickup($lat,$lon)',
        ),
        (double puLat, double puLon, double drLat, double drLon) => _controller.runJavaScript(
          'setPointsFromFlutter($puLat,$puLon,$drLat,$drLon)',
        ),
        (double lat, double lon) => _controller.runJavaScript(
          'prefillPickupSilent($lat,$lon)',
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = WebViewWidget(controller: _controller);
    if (widget.clean) {
      return IgnorePointer(ignoring: true, child: view);
    }
    return view;
  }
}
