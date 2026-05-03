// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'yandex_order_map_html.dart';

/// Яндекс.Карта во встроенном iframe (Flutter Web). `webview_flutter_web` не поддерживает JS-каналы.
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

  /// Поле Яндекс Suggest над картой (например экран полноэкранной карты из выбора адреса).
  final bool showAddressSearch;

  /// Один маркер / два подряд (см. встроенный HTML).
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
  late final String _viewType;
  late final html.IFrameElement _iframe;
  StreamSubscription<html.Event>? _loadSub;
  StreamSubscription<html.MessageEvent>? _msgSub;
  bool _bridgeReady = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'invo-yandex-${identityHashCode(this)}-${DateTime.now().microsecondsSinceEpoch}';
    _iframe = html.IFrameElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..style.pointerEvents = widget.clean ? 'none' : 'auto'
      ..srcdoc = buildYandexOrderMapHtml(
        apiKey: widget.apiKey,
        bridgeScript: yandexMapBridgeIframe,
        visualLightBackground: widget.visualLightBackground,
        showAddressSearch: widget.showAddressSearch,
        interactionMode: widget.interactionMode,
      );

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _iframe);

    _msgSub = html.window.onMessage.listen((html.MessageEvent e) {
      final d = e.data;
      if (d is! String || !d.startsWith('invo_yandex:')) return;
      widget.onPayload(d.substring('invo_yandex:'.length));
    });

    _loadSub = _iframe.onLoad.listen((_) {
      if (_bridgeReady) return;
      _bridgeReady = true;
      void post(String msg) => _iframe.contentWindow?.postMessage(msg, '*');
      widget.onBridgeReady(
        () async => post('invo_apply'),
        () async => post('invo_reset'),
        (double lat, double lon, {int? zoom}) async =>
            post('invo_center:$lat,$lon,${zoom ?? 14}'),
        (double lat, double lon) async => post('invo_gps:$lat,$lon'),
        (double puLat, double puLon, double drLat, double drLon) async =>
            post('invo_setpoints:$puLat,$puLon,$drLat,$drLon'),
        (double lat, double lon) async => post('invo_prefill_pickup:$lat,$lon'),
      );
    });
  }

  @override
  void dispose() {
    _loadSub?.cancel();
    _msgSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
