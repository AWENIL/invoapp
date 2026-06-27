import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

typedef DriverNavStartFn = void Function(
  double fromLat,
  double fromLon,
  double toLat,
  double toLon,
  String routeJson,
);
typedef DriverNavUpdateFn = void Function(double lat, double lon, double heading);
typedef DriverNavFollowFn = void Function(bool enabled, {double? zoom});
typedef DriverNavClearFn = void Function();
typedef DriverNavBridgeReady = void Function(
  DriverNavStartFn startDriverNav,
  DriverNavUpdateFn updateDriverPosition,
  DriverNavFollowFn setFollowMode,
  DriverNavClearFn clearDriverNav,
);

class DriverNavigationMapEmbed extends StatefulWidget {
  const DriverNavigationMapEmbed({
    super.key,
    required this.apiKey,
    required this.onBridgeReady,
  });

  final String apiKey;
  final DriverNavBridgeReady onBridgeReady;

  @override
  State<DriverNavigationMapEmbed> createState() => _DriverNavigationMapEmbedState();
}

class _DriverNavigationMapEmbedState extends State<DriverNavigationMapEmbed> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(_html(widget.apiKey));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onBridgeReady(
        (fromLat, fromLon, toLat, toLon, routeJson) {
          _controller.runJavaScript(
            'window.startDriverNav && window.startDriverNav($fromLat,$fromLon,$toLat,$toLon, $routeJson);',
          );
        },
        (lat, lon, heading) {
          _controller.runJavaScript(
            'window.updateDriverPosition && window.updateDriverPosition($lat,$lon,$heading);',
          );
        },
        (enabled, {zoom}) {
          final z = zoom ?? 17;
          _controller.runJavaScript('window.setFollowMode && window.setFollowMode($enabled,$z);');
        },
        () {
          _controller.runJavaScript('window.clearDriverNav && window.clearDriverNav();');
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

String _html(String apiKey) {
  return '''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    html, body, #map { width: 100%; height: 100%; margin: 0; background: #e8e8e8; }
  </style>
  <script src="https://api-maps.yandex.ru/2.1/?apikey=$apiKey&lang=ru_RU"></script>
</head>
<body>
  <div id="map"></div>
  <script>
    let map, routeLine, driverMarker, follow = false, followZoom = 17;
    ymaps.ready(() => {
      map = new ymaps.Map('map', { center: [43.238949, 76.889709], zoom: 13, controls: [] });
      window.startDriverNav = (fromLat, fromLon, toLat, toLon, routeJson) => {
        const route = JSON.parse(JSON.stringify(routeJson));
        const points = typeof route === 'string' ? JSON.parse(route) : route;
        map.geoObjects.removeAll();
        routeLine = new ymaps.Polyline(points, {}, { strokeColor: '#ff6b44', strokeWidth: 6, strokeOpacity: 0.95 });
        const finish = new ymaps.Placemark([toLat, toLon], {}, { preset: 'islands#redCircleDotIcon' });
        driverMarker = new ymaps.Placemark([fromLat, fromLon], {}, { preset: 'islands#blueCircleDotIcon' });
        map.geoObjects.add(routeLine).add(finish).add(driverMarker);
        const bounds = routeLine.geometry.getBounds();
        if (bounds) map.setBounds(bounds, { checkZoomRange: true, zoomMargin: 56 });
      };
      window.updateDriverPosition = (lat, lon, heading) => {
        if (!driverMarker) {
          driverMarker = new ymaps.Placemark([lat, lon], {}, { preset: 'islands#blueCircleDotIcon' });
          map.geoObjects.add(driverMarker);
        } else {
          driverMarker.geometry.setCoordinates([lat, lon]);
        }
        if (follow) map.setCenter([lat, lon], followZoom);
      };
      window.setFollowMode = (enabled, zoom) => { follow = enabled; followZoom = zoom || 17; };
      window.clearDriverNav = () => map.geoObjects.removeAll();
    });
  </script>
</body>
</html>
''';
}
