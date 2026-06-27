String yandexOrderMapHtml({
  required String apiKey,
  bool visualLightBackground = false,
}) {
  final background = visualLightBackground ? '#f8f0ec' : '#ffffff';
  return '''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    html, body, #map { width: 100%; height: 100%; margin: 0; background: $background; }
  </style>
  <script src="https://api-maps.yandex.ru/2.1/?apikey=$apiKey&lang=ru_RU"></script>
</head>
<body>
  <div id="map"></div>
  <script>
    let map, pickup, dropoff, routeLine;
    ymaps.ready(() => {
      map = new ymaps.Map('map', { center: [43.238949, 76.889709], zoom: 12, controls: [] });
      window.setPoints = (puLat, puLon, drLat, drLon) => {
        const from = [puLat, puLon], to = [drLat, drLon];
        map.geoObjects.removeAll();
        pickup = new ymaps.Placemark(from, {}, { preset: 'islands#orangeCircleDotIcon' });
        dropoff = new ymaps.Placemark(to, {}, { preset: 'islands#redCircleDotIcon' });
        routeLine = new ymaps.Polyline([from, to], {}, { strokeColor: '#ff6b44', strokeWidth: 5 });
        map.geoObjects.add(routeLine).add(pickup).add(dropoff);
        map.setBounds(map.geoObjects.getBounds(), { checkZoomRange: true, zoomMargin: 40 });
      };
    });
  </script>
</body>
</html>
''';
}
