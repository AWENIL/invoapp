import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/env.dart';
import 'yandex_order_map_embed_io.dart'
    if (dart.library.html) 'yandex_order_map_embed_web.dart';
import 'yandex_order_map_html.dart';

String yandexRouteUrl(double fromLat, double fromLon, double toLat, double toLon) =>
    'https://yandex.ru/maps/?mode=routes&rtext=$fromLat,$fromLon~$toLat,$toLon';

/// Один сегмент маршрута A→B: Яндекс JS API при непустом ключе, иначе WebView страницы маршрута Яндекса.
class TripSegmentMap extends StatefulWidget {
  const TripSegmentMap({
    super.key,
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
    this.mapHeight = 280,
    this.apiKey = yandexMapsApiKey,
    /// Если false — только карта заданной высоты (для встраивания в фиксированный блок без overflow).
    this.showOpenInExternalMapsButton = true,
  });

  final double fromLat;
  final double fromLon;
  final double toLat;
  final double toLon;
  final double mapHeight;
  final String apiKey;
  final bool showOpenInExternalMapsButton;

  @override
  State<TripSegmentMap> createState() => _TripSegmentMapState();
}

class _TripSegmentMapState extends State<TripSegmentMap> {
  void Function(double puLat, double puLon, double drLat, double drLon)? _setPoints;

  bool get _useJsApi => widget.apiKey.trim().isNotEmpty;

  void _pushSegment() {
    final cb = _setPoints;
    if (cb == null) return;
    cb(widget.fromLat, widget.fromLon, widget.toLat, widget.toLon);
  }

  @override
  void didUpdateWidget(TripSegmentMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fromLat != widget.fromLat ||
        oldWidget.fromLon != widget.fromLon ||
        oldWidget.toLat != widget.toLat ||
        oldWidget.toLon != widget.toLon) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_useJsApi) {
          _pushSegment();
        }
      });
    }
  }

  Future<void> _openYandexApp() async {
    final u = Uri.parse(
      yandexRouteUrl(widget.fromLat, widget.fromLon, widget.toLat, widget.toLon),
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
    if (_useJsApi) {
      final mapBlock = SizedBox(
        height: widget.mapHeight,
        child: ColoredBox(
          color: const Color(0xFFF8F0EC),
          child: YandexOrderMapEmbed(
            apiKey: widget.apiKey,
            visualLightBackground: true,
            showAddressSearch: false,
            interactionMode: YandexOrderMapInteractionMode.routeDisplayOnly,
            onPayload: (_) {},
            onBridgeReady: (
              apply,
              reset,
              centerMap,
              gpsAsPickup,
              setPoints,
              prefillPickupSilent,
            ) {
              _setPoints = setPoints;
              WidgetsBinding.instance.addPostFrameCallback((_) => _pushSegment());
            },
          ),
        ),
      );
      if (!widget.showOpenInExternalMapsButton) {
        return mapBlock;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          mapBlock,
          TextButton.icon(
            onPressed: _openYandexExternally,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Открыть в приложении карт'),
          ),
        ],
      );
    }

    return _YandexSiteRouteEmbed(
      fromLat: widget.fromLat,
      fromLon: widget.fromLon,
      toLat: widget.toLat,
      toLon: widget.toLon,
      mapHeight: widget.mapHeight,
      onOpenExternal: _openYandexApp,
      showFooterButton: widget.showOpenInExternalMapsButton,
    );
  }
}

/// Встраивание через сайт Яндекса (WebView на нативных платформах; на web — кнопка открыть).
class _YandexSiteRouteEmbed extends StatefulWidget {
  const _YandexSiteRouteEmbed({
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
    required this.mapHeight,
    required this.onOpenExternal,
    this.showFooterButton = true,
  });

  final double fromLat;
  final double fromLon;
  final double toLat;
  final double toLon;
  final double mapHeight;
  final VoidCallback onOpenExternal;
  final bool showFooterButton;

  @override
  State<_YandexSiteRouteEmbed> createState() => _YandexSiteRouteEmbedState();
}

class _YandexSiteRouteEmbedState extends State<_YandexSiteRouteEmbed> {
  WebViewController? _controller;

  Uri _uri() => Uri.parse(
        yandexRouteUrl(
          widget.fromLat,
          widget.fromLon,
          widget.toLat,
          widget.toLon,
        ),
      );

  void _load() {
    _controller?.loadRequest(_uri());
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(_uri());
    }
  }

  @override
  void didUpdateWidget(_YandexSiteRouteEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fromLat != widget.fromLat ||
        oldWidget.fromLon != widget.fromLon ||
        oldWidget.toLat != widget.toLat ||
        oldWidget.toLon != widget.toLon) {
      if (!kIsWeb) {
        _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final mapBlock = SizedBox(
        height: widget.mapHeight,
        child: ColoredBox(
          color: const Color(0xFFF5F5F5),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map_outlined, size: 40, color: Colors.grey),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: widget.onOpenExternal,
                    child: const Text('Открыть маршрут в Яндекс.Картах'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (!widget.showFooterButton) return mapBlock;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          mapBlock,
          TextButton.icon(
            onPressed: widget.onOpenExternal,
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('Яндекс.Карты'),
          ),
        ],
      );
    }

    if (!widget.showFooterButton) {
      return SizedBox(
        height: widget.mapHeight,
        child: WebViewWidget(controller: _controller!),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.mapHeight,
          child: WebViewWidget(controller: _controller!),
        ),
        TextButton.icon(
          onPressed: widget.onOpenExternal,
          icon: const Icon(Icons.map_outlined),
          label: const Text('Открыть в приложении карт'),
        ),
      ],
    );
  }
}
