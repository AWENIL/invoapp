import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:invo_common/invo_common.dart';
import 'package:invo_common/widgets/driver_navigation_map_embed_io.dart'
    show DriverNavFollowFn, DriverNavStartFn, DriverNavUpdateFn, DriverNavigationMapEmbed;

class DriverNavigationMap extends StatefulWidget {
  const DriverNavigationMap({
    super.key,
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
    required this.routePoints,
    this.driverLat,
    this.driverLon,
    this.driverHeading = 0,
    this.apiKey = yandexMapsApiKey,
  });

  final double fromLat;
  final double fromLon;
  final double toLat;
  final double toLon;
  final List<List<double>> routePoints;
  final double? driverLat;
  final double? driverLon;
  final double driverHeading;
  final String apiKey;

  @override
  State<DriverNavigationMap> createState() => _DriverNavigationMapState();
}

class _DriverNavigationMapState extends State<DriverNavigationMap> {
  DriverNavStartFn? _startDriverNav;
  DriverNavUpdateFn? _updateDriverPosition;
  DriverNavFollowFn? _setFollowMode;
  bool _followEnabled = false;
  bool _routeStarted = false;

  String _routeJson() => jsonEncode(widget.routePoints);

  void _pushRouteIfReady() {
    final start = _startDriverNav;
    if (start == null || _routeStarted) return;
    _routeStarted = true;
    start(
      widget.fromLat,
      widget.fromLon,
      widget.toLat,
      widget.toLon,
      _routeJson(),
    );
    _setFollowMode?.call(true, zoom: 17);
    _followEnabled = true;
    final lat = widget.driverLat ?? widget.fromLat;
    final lon = widget.driverLon ?? widget.fromLon;
    _updateDriverPosition?.call(lat, lon, widget.driverHeading);
  }

  void _pushDriverPosition() {
    final lat = widget.driverLat;
    final lon = widget.driverLon;
    final update = _updateDriverPosition;
    if (lat == null || lon == null || update == null) return;
    update(lat, lon, widget.driverHeading);
    if (!_followEnabled) {
      _setFollowMode?.call(true, zoom: 17);
      _followEnabled = true;
    }
  }

  @override
  void didUpdateWidget(DriverNavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.toLat != widget.toLat ||
        oldWidget.toLon != widget.toLon ||
        oldWidget.fromLat != widget.fromLat ||
        oldWidget.fromLon != widget.fromLon ||
        oldWidget.routePoints.length != widget.routePoints.length) {
      _routeStarted = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _pushRouteIfReady());
    } else if (oldWidget.driverLat != widget.driverLat ||
        oldWidget.driverLon != widget.driverLon ||
        oldWidget.driverHeading != widget.driverHeading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pushDriverPosition());
    }
  }

  @override
  void dispose() {
    _setFollowMode?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.apiKey.trim().isEmpty) {
      return ColoredBox(
        color: const Color(0xFFE8E8E8),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Для навигации нужен ключ Yandex Maps (YANDEX_MAPS_API_KEY).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        ),
      );
    }

    return DriverNavigationMapEmbed(
      apiKey: widget.apiKey,
      onBridgeReady: (startDriverNav, updateDriverPosition, setFollowMode, clearDriverNav) {
        _startDriverNav = startDriverNav;
        _updateDriverPosition = updateDriverPosition;
        _setFollowMode = setFollowMode;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _pushRouteIfReady();
          _pushDriverPosition();
        });
      },
    );
  }
}
