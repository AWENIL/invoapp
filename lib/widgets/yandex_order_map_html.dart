/// Режим выбора точек на встроенной HTML-карте.
enum YandexOrderMapInteractionMode {
  both,
  pickupOnly,
  dropoffOnly,

  /// Только отображение выбранных точек и маршрута (главная; выбор через bottom sheet).
  routeDisplayOnly,
}

/// HTML для Яндекс.Карт: поиск (SuggestView), два клика, геокодер, команды из Flutter.
///
/// [visualLightBackground] — светлый «фоновый» режим для главной: без панели поиска,
/// светлая подложка и лёгкая десатурация карты (жесты при необходимости режет Flutter `clean`).
String buildYandexOrderMapHtml({
  required String apiKey,
  required String bridgeScript,
  bool visualLightBackground = false,
  bool showAddressSearch = false,
  YandexOrderMapInteractionMode interactionMode =
      YandexOrderMapInteractionMode.both,
}) {
  final wrapBg = visualLightBackground ? '#F8F0EC' : '#121218';
  final searchBoxCss = visualLightBackground && !showAddressSearch
      ? 'display: none;'
      : visualLightBackground && showAddressSearch
          ? '''
    padding: 10px 12px;
    background: #f5f6f8;
    border-bottom: 1px solid #dadce0;
    z-index: 1002;
  '''
          : '''
    padding: 8px 10px;
    background: #1e1e24;
    border-bottom: 1px solid #333;
    z-index: 1002;
  ''';
  final searchInputExtras = visualLightBackground && showAddressSearch
      ? 'background: #fff; border: 1px solid #dadce0;'
      : '';
  final hintCss = visualLightBackground && !showAddressSearch
      ? 'display: none;'
      : visualLightBackground && showAddressSearch
          ? '''
    position: absolute; bottom: 12px; left: 12px; right: 12px;
    background: rgba(255,255,255,.94); color: #3c4043; padding: 8px 10px;
    border-radius: 10px; font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    font-size: 12px; line-height: 1.35; z-index: 1000; pointer-events: none;
    border: 1px solid rgba(0,0,0,.06); box-shadow: 0 2px 8px rgba(0,0,0,.06);
  '''
          : '''
    position: absolute; top: 10px; left: 10px; right: 10px;
    background: rgba(0,0,0,.78); color: #fff; padding: 10px 12px;
    border-radius: 10px; font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    font-size: 13px; line-height: 1.35; z-index: 1000; pointer-events: none;
  ''';
  final mapWrapFilter = visualLightBackground ? 'filter: saturate(0.72) brightness(1.04);' : '';
  final mapModeJs = switch (interactionMode) {
    YandexOrderMapInteractionMode.both => 'both',
    YandexOrderMapInteractionMode.pickupOnly => 'pickup_only',
    YandexOrderMapInteractionMode.dropoffOnly => 'dropoff_only',
    YandexOrderMapInteractionMode.routeDisplayOnly => 'route_display_only',
  };
  final gpsBtnDisplay = switch (interactionMode) {
    YandexOrderMapInteractionMode.dropoffOnly => 'none',
    YandexOrderMapInteractionMode.routeDisplayOnly => 'none',
    _ => 'flex',
  };

  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; height: 100%; }
  #wrap { display: flex; flex-direction: column; height: 100vh; background: $wrapBg; }
  #search-box {
    $searchBoxCss
  }
  #search-input {
    width: 100%;
    padding: 12px 14px;
    border-radius: 10px;
    border: none;
    font-size: 16px;
    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  }
  #map-wrap { position: relative; flex: 1; min-height: 0; $mapWrapFilter }
  #map { width: 100%; height: 100%; }
  #hint {
    $hintCss
  }
  #gps-btn {
    position: absolute;
    right: 12px;
    top: 12px;
    width: 44px;
    height: 44px;
    border-radius: 14px;
    background: rgba(255, 255, 255, 0.92);
    border: 1px solid rgba(0,0,0,0.08);
    box-shadow: 0 6px 18px rgba(0,0,0,0.12);
    display: $gpsBtnDisplay;
    align-items: center;
    justify-content: center;
    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    cursor: pointer;
    user-select: none;
    z-index: 1003;
  }
  #gps-btn:active { transform: scale(0.98); }
  /* Текст про Яндекс/условия в углу: классы API меняются между версиями */
  #map [class*="copyrights-pane"] {
    visibility: hidden !important;
    pointer-events: none !important;
    max-height: 0 !important;
    opacity: 0 !important;
    overflow: hidden !important;
  }
</style>
<script src="https://api-maps.yandex.ru/2.1/?apikey=$apiKey&lang=ru_RU"></script>
</head>
<body>
<div id="wrap">
  <div id="search-box">
    <input id="search-input" type="text" autocomplete="off" placeholder="Поиск адреса…" style="$searchInputExtras" />
  </div>
  <div id="map-wrap">
    <div id="hint">${visualLightBackground && showAddressSearch ? 'Нажмите на карту или найдите адрес. При двух точках двигается ближайшая метка.' : 'Сначала откуда, затем куда — нажмите на карту. Или найдите адрес выше.'}</div>
    <div id="gps-btn" title="Моё местоположение">⌖</div>
    <div id="map"></div>
  </div>
</div>
<script>
var MAP_MODE = '$mapModeJs';
var SHOW_ADDRESS_SEARCH = ${showAddressSearch ? 'true' : 'false'};
$bridgeScript

var pickup = null;
var dropoff = null;
var placemarkA = null;
var placemarkB = null;
var searchPlacemark = null;
var routeLine = null;
var map = null;
var suggestView = null;
var deferredUntilMap = [];

function runWhenMapReady(fn) {
  if (map) {
    try { fn(); } catch (e) {}
  } else {
    deferredUntilMap.push(fn);
  }
}

function flushDeferredMapCommands() {
  if (!map) return;
  while (deferredUntilMap.length) {
    var fn = deferredUntilMap.shift();
    try {
      fn();
    } catch (e) {}
  }
}

function emitProgressToFlutter() {
  try {
    var payload = { progress_only: true };
    if (pickup) {
      payload.pickup_lat = pickup[0];
      payload.pickup_lon = pickup[1];
      payload.pickup_address = pickup[2] || '';
    }
    if (dropoff) {
      payload.dropoff_lat = dropoff[0];
      payload.dropoff_lon = dropoff[1];
      payload.dropoff_address = dropoff[2] || '';
    }
    toFlutter(JSON.stringify(payload));
  } catch (e) {}
}

function setHint(t) {
  var el = document.getElementById('hint');
  if (el) el.textContent = t;
}

function geocode(coords, cb) {
  ymaps.geocode(coords, { results: 1 }).then(function (res) {
    var f = res.geoObjects.get(0);
    cb(f ? f.getAddressLine() : '');
  }, function () { cb(''); });
}

function coordDist2ToPoint(c, plat, plon) {
  var dx = c[0] - plat, dy = c[1] - plon;
  return dx * dx + dy * dy;
}

function pickupCloserThanDropoffCoords(c) {
  if (!pickup || !dropoff) return true;
  var da = coordDist2ToPoint(c, pickup[0], pickup[1]);
  var db = coordDist2ToPoint(c, dropoff[0], dropoff[1]);
  return da <= db;
}

function clearRoute() {
  if (!map) return;
  if (routeLine) {
    try { map.geoObjects.remove(routeLine); } catch (e) {}
    routeLine = null;
  }
}

function updateRouteIfReady() {
  if (!map) return;
  if (!pickup || !dropoff) {
    clearRoute();
    return;
  }
  var a = [pickup[0], pickup[1]];
  var b = [dropoff[0], dropoff[1]];
  clearRoute();
  try {
    routeLine = new ymaps.multiRouter.MultiRoute(
      { referencePoints: [a, b], params: { routingMode: 'auto' } },
      {
        boundsAutoApply: false,
        // Не показывать панель/балун с «N мин», «Подробнее» и переходами в приложение Карт.
        balloonPanelMaxMapArea: 0,
        routeOpenBalloonOnClick: false,
        routeBalloonVisible: false,
        routeActiveBalloonVisible: false,
        routeMarkerVisible: false,
        routeWalkMarkerVisible: false,
        // Точки отправления/приезда задаём своими маркерами Flutter; у маршрута — только линия.
        pinVisible: false,
        wayPointVisible: false,
        routeActiveStrokeColor: 'fe633d',
        routeStrokeColor: 'ffc5b7',
        routeActiveStrokeWidth: 5,
        routeStrokeWidth: 4,
      }
    );
    map.geoObjects.add(routeLine);
    suppressMultiRouteBalloon(routeLine);
  } catch (e) {
    // If router isn't available (rare), just keep markers.
  }
}

function suppressMultiRouteBalloon(multiRoute) {
  try {
    multiRoute.events.add('balloonopen', function (e) {
      try {
        var t = e.get('originalTarget');
        if (t && t.balloon && typeof t.balloon.close === 'function') t.balloon.close();
      } catch (ignore) {}
    });
  } catch (ignore2) {}
}

function fitToPoints(a, b) {
  if (!map) return;
  var lat1 = a[0], lon1 = a[1], lat2 = b[0], lon2 = b[1];
  if (!(isFinite(lat1) && isFinite(lon1) && isFinite(lat2) && isFinite(lon2))) return;
  // setBounds принимает [ЮЗ-угол, СВ-угол]; две точки нужно упорядочить, иначе карта может уйти в «весь мир».
  var south = Math.min(lat1, lat2);
  var north = Math.max(lat1, lat2);
  var west = Math.min(lon1, lon2);
  var east = Math.max(lon1, lon2);
  try {
    if (Math.abs(north - south) < 1e-9 && Math.abs(east - west) < 1e-9) {
      map.setCenter([lat1, lon1], 15, { duration: 300 });
      return;
    }
    map.setBounds(
      [[south, west], [north, east]],
      { checkZoomRange: true, zoomMargin: 48, duration: 300 }
    );
  } catch (e) {
    try {
      map.setCenter([(lat1 + lat2) * 0.5, (lon1 + lon2) * 0.5], 14, { duration: 300 });
    } catch (e2) {
      map.setCenter([lat1, lon1], 14, { duration: 300 });
    }
  }
}

function ensurePlacemarkA(c) {
  if (!map) return;
  if (placemarkA) {
    try { placemarkA.geometry.setCoordinates(c); } catch (e) {}
    return;
  }
  placemarkA = new ymaps.Placemark(c, { balloonContent: 'Откуда' }, { preset: 'islands#darkOrangeDotIcon' });
  map.geoObjects.add(placemarkA);
}

function ensurePlacemarkB(c) {
  if (!map) return;
  if (placemarkB) {
    try { placemarkB.geometry.setCoordinates(c); } catch (e) {}
    return;
  }
  placemarkB = new ymaps.Placemark(c, { balloonContent: 'Куда' }, { preset: 'islands#redDotIcon' });
  map.geoObjects.add(placemarkB);
}

function setPointsFromFlutter(puLat, puLon, drLat, drLon) {
  var a = [puLat, puLon];
  var b = [drLat, drLon];

  if (searchPlacemark) {
    try { map.geoObjects.remove(searchPlacemark); } catch (x) {}
    searchPlacemark = null;
  }

  pickup = [puLat, puLon, pickup ? (pickup[2] || '') : ''];
  dropoff = [drLat, drLon, dropoff ? (dropoff[2] || '') : ''];

  ensurePlacemarkA(a);
  ensurePlacemarkB(b);
  setHint('Точки выбраны.');
  fitToPoints(a, b);
  updateRouteIfReady();
  emitProgressToFlutter();

  // Optional: refresh address lines so Flutter gets nice titles on "apply"
  geocode(a, function (addr) { try { pickup[2] = addr; } catch (e) {} });
  geocode(b, function (addr) { try { dropoff[2] = addr; } catch (e) {} });
}

function applyPartialPickupToFlutter() {
  try {
    if (!pickup) return;
    toFlutter(JSON.stringify({
      partial: true,
      edited_field: 'pickup',
      pickup_lat: pickup[0],
      pickup_lon: pickup[1],
      pickup_address: pickup[2] || ''
    }));
  } catch (e) {}
}

function applyPartialDropoffToFlutter() {
  try {
    if (!pickup || !dropoff) return;
    toFlutter(JSON.stringify({
      partial: true,
      edited_field: 'dropoff',
      pickup_lat: pickup[0],
      pickup_lon: pickup[1],
      pickup_address: pickup[2] || '',
      dropoff_lat: dropoff[0],
      dropoff_lon: dropoff[1],
      dropoff_address: dropoff[2] || ''
    }));
  } catch (e) {}
}

function applyToFlutter() {
  if (!pickup || !dropoff) {
    toFlutter('{}');
    return;
  }
  toFlutter(JSON.stringify({
    pickup_lat: pickup[0],
    pickup_lon: pickup[1],
    pickup_address: pickup[2] || '',
    dropoff_lat: dropoff[0],
    dropoff_lon: dropoff[1],
    dropoff_address: dropoff[2] || ''
  }));
}

function resetHintAfterClear() {
  if (SHOW_ADDRESS_SEARCH) {
    setHint('Нажмите на карту или найдите адрес. При двух точках двигается ближайшая метка.');
    return;
  }
  if (MAP_MODE === 'route_display_only') {
    setHint('');
    return;
  }
  if (MAP_MODE === 'pickup_only') setHint('Укажите точку посадки на карте или в поиске.');
  else if (MAP_MODE === 'dropoff_only') setHint('Укажите пункт назначения на карте или в поиске.');
  else setHint('Сначала откуда, затем куда — нажмите на карту.');
}

function resetPoints() {
  pickup = null;
  dropoff = null;
  if (map) {
    if (placemarkA) { map.geoObjects.remove(placemarkA); placemarkA = null; }
    if (placemarkB) { map.geoObjects.remove(placemarkB); placemarkB = null; }
    if (searchPlacemark) { map.geoObjects.remove(searchPlacemark); searchPlacemark = null; }
    clearRoute();
  }
  resetHintAfterClear();
  emitProgressToFlutter();
}

function centerFromFlutter(lat, lon, zoom) {
  if (!map) return;
  var z = zoom || 14;
  map.setCenter([lat, lon], z, { duration: 300 });
}

function applyGpsAsPickup(lat, lon) {
  if (!map) return;
  if (MAP_MODE === 'dropoff_only') return;
  if (MAP_MODE === 'route_display_only') return;
  resetPoints();
  var c = [lat, lon];
  pickup = [lat, lon, ''];
  placemarkA = new ymaps.Placemark(c, { balloonContent: 'Откуда (геопозиция)' }, { preset: 'islands#darkOrangeDotIcon' });
  map.geoObjects.add(placemarkA);
  map.setCenter(c, 15, { duration: 300 });
  // Сразу передаём посадку в Flutter (без ожидания геокодера Яндекса), чтобы можно было закрыть карту тем же действием — и pickup_only и both.
  if (MAP_MODE === 'pickup_only' || MAP_MODE === 'both') {
    applyPartialPickupToFlutter();
  }
  geocode(c, function (addr) {
    try { pickup[2] = addr; } catch (e) {}
    if (MAP_MODE === 'pickup_only') {
      setHint('Точка посадки выбрана.');
      emitProgressToFlutter();
      return;
    }
    if (MAP_MODE === 'both') {
      setHint('');
      emitProgressToFlutter();
      return;
    }
    emitProgressToFlutter();
  });
}

function prefillPickupSilent(lat, lon) {
  if (MAP_MODE === 'route_display_only') return;
  var c = [lat, lon];
  if (MAP_MODE === 'pickup_only') {
    pickup = [lat, lon, ''];
    ensurePlacemarkA(c);
    if (placemarkB) { try { map.geoObjects.remove(placemarkB); } catch (x) {} placemarkB = null; }
    dropoff = null;
    clearRoute();
    updateRouteIfReady();
    map.setCenter(c, 15, { duration: 300 });
    setHint(SHOW_ADDRESS_SEARCH ? 'Точка на карте. Нажмите или найдите адрес, чтобы изменить.' : 'Точка посадки на карте.');
    geocode(c, function (addr) {
      try { pickup[2] = addr; } catch (e) {}
      emitProgressToFlutter();
    });
    emitProgressToFlutter();
    return;
  }
  if (MAP_MODE === 'dropoff_only') {
    pickup = [lat, lon, ''];
    ensurePlacemarkA(c);
    map.setCenter(c, 14, { duration: 300 });
    setHint(SHOW_ADDRESS_SEARCH ? 'Укажите куда на карте или в поиске.' : 'Укажите пункт назначения на карте или в поиске.');
    geocode(c, function (addr) {
      try { pickup[2] = addr; } catch (e) {}
      emitProgressToFlutter();
    });
    emitProgressToFlutter();
    return;
  }
  pickup = [lat, lon, ''];
  ensurePlacemarkA(c);
  if (placemarkB) { try { map.geoObjects.remove(placemarkB); } catch (x) {} placemarkB = null; }
  dropoff = null;
  clearRoute();
  updateRouteIfReady();
  map.setCenter(c, 15, { duration: 300 });
  setHint(SHOW_ADDRESS_SEARCH ? 'Теперь укажите куда на карте или в поиске.' : 'Теперь укажите куда (клик по карте).');
  geocode(c, function (addr) {
    try { pickup[2] = addr; } catch (e) {}
    emitProgressToFlutter();
  });
  emitProgressToFlutter();
}

window.addEventListener('message', function (e) {
  var d = e.data;
  if (typeof d !== 'string') return;
  if (d === 'invo_apply') { try { applyToFlutter(); } catch (err) {} return; }
  if (d === 'invo_reset') {
    runWhenMapReady(function () {
      try { resetPoints(); } catch (err) {}
    });
    return;
  }
  if (d.indexOf('invo_setpoints:') === 0) {
    // Было substring(14) — лишним оставался «:», parseFloat давал NaN, маркеры и маршрут не ставились.
    var sp = d.substring('invo_setpoints:'.length).split(',');
    var puLa = parseFloat(sp[0]), puLo = parseFloat(sp[1]), drLa = parseFloat(sp[2]), drLo = parseFloat(sp[3]);
    if (!isNaN(puLa) && !isNaN(puLo) && !isNaN(drLa) && !isNaN(drLo)) {
      runWhenMapReady(function () {
        try { setPointsFromFlutter(puLa, puLo, drLa, drLo); } catch (err) {}
      });
    }
    return;
  }
  if (d.indexOf('invo_center:') === 0) {
    var rest = d.substring(12).split(',');
    var la = parseFloat(rest[0]), lo = parseFloat(rest[1]), z = parseInt(rest[2] || '14', 10);
    if (!isNaN(la) && !isNaN(lo)) {
      runWhenMapReady(function () {
        try { centerFromFlutter(la, lo, z); } catch (err) {}
      });
    }
    return;
  }
  if (d.indexOf('invo_gps:') === 0) {
    var r = d.substring(9).split(',');
    var la2 = parseFloat(r[0]), lo2 = parseFloat(r[1]);
    if (!isNaN(la2) && !isNaN(lo2)) {
      runWhenMapReady(function () {
        try { applyGpsAsPickup(la2, lo2); } catch (err) {}
      });
    }
    return;
  }
  if (d.indexOf('invo_prefill_pickup:') === 0) {
    var pf = d.substring(20).split(',');
    var pLa = parseFloat(pf[0]), pLo = parseFloat(pf[1]);
    if (!isNaN(pLa) && !isNaN(pLo)) {
      runWhenMapReady(function () {
        try { prefillPickupSilent(pLa, pLo); } catch (err2) {}
      });
    }
    return;
  }
});

ymaps.ready(function () {
  map = new ymaps.Map(
    'map',
    {
      center: [47.1167, 51.8833],
      zoom: 12,
      controls: [],
    },
    {
      suppressMapOpenBlock: true,
      yandexMapDisablePoiInteractivity: true,
    },
  );

  var gpsBtn = document.getElementById('gps-btn');
  if (gpsBtn) {
    gpsBtn.addEventListener('click', function () {
      if (!navigator.geolocation) {
        setHint('Геолокация недоступна на устройстве.');
        return;
      }
      setHint('Определяем местоположение…');
      navigator.geolocation.getCurrentPosition(function (pos) {
        try {
          var la = pos.coords.latitude;
          var lo = pos.coords.longitude;
          applyGpsAsPickup(la, lo);
        } catch (e) {
          setHint('Не удалось получить координаты.');
        }
      }, function (err) {
        setHint('Не удалось получить местоположение. Разрешите доступ к геолокации.');
      }, { enableHighAccuracy: true, timeout: 10000, maximumAge: 5000 });
    });
  }

  if (MAP_MODE !== 'route_display_only') try {
    suggestView = new ymaps.SuggestView('search-input', { boundedBy: map.getBounds(), strictBounds: false });
    suggestView.events.add('select', function (e) {
      var item = e.get('item');
      if (!item) return;
      var query = (item.value != null ? item.value : '') + '';
      if (!query && item.displayName) query = item.displayName + '';
      if (!query) return;
      ymaps.geocode(query, { results: 1 }).then(function (res) {
        var obj = res.geoObjects.get(0);
        if (!obj) return;
        var c = obj.geometry.getCoordinates();
        if (searchPlacemark) { try { map.geoObjects.remove(searchPlacemark); } catch (x) {} searchPlacemark = null; }

        if (MAP_MODE === 'pickup_only') {
          pickup = [c[0], c[1], query];
          ensurePlacemarkA(c);
          if (placemarkB) { try { map.geoObjects.remove(placemarkB); } catch (x) {} placemarkB = null; }
          dropoff = null;
          clearRoute();
          updateRouteIfReady();
          map.setCenter(c, 15, { duration: 300 });
          setHint('Точка посадки выбрана.');
          geocode(c, function (addr) {
            try { pickup[2] = addr || query; } catch (e) {}
            emitProgressToFlutter();
            try { applyPartialPickupToFlutter(); } catch (ex) {}
          });
          emitProgressToFlutter();
          return;
        }

        if (MAP_MODE === 'dropoff_only') {
          if (!pickup) {
            setHint('Сначала выберите точку посадки в приложении.');
            return;
          }
          dropoff = [c[0], c[1], query];
          ensurePlacemarkB(c);
          setHint('Пункт назначения выбран.');
          updateRouteIfReady();
          map.setCenter(c, 15, { duration: 300 });
          geocode(c, function (addr) {
            try { dropoff[2] = addr || query; } catch (e) {}
            updateRouteIfReady();
            emitProgressToFlutter();
            try { applyPartialDropoffToFlutter(); } catch (e2) {}
          });
          emitProgressToFlutter();
          try { fitToPoints([pickup[0], pickup[1]], [dropoff[0], dropoff[1]]); } catch (e3) {}
          return;
        }

        if (!pickup) {
          pickup = [c[0], c[1], query];
          ensurePlacemarkA(c);
          updateRouteIfReady();
          map.setCenter(c, 15, { duration: 300 });
          setHint('Теперь укажите куда (поиск или клик по карте).');
          geocode(c, function (addr) {
            try { pickup[2] = addr || query; } catch (e) {}
            emitProgressToFlutter();
          });
          emitProgressToFlutter();
          return;
        }
        if (!dropoff) {
          dropoff = [c[0], c[1], query];
          ensurePlacemarkB(c);
          setHint('Точки выбраны.');
          geocode(c, function (addr) {
            try { dropoff[2] = addr || query; } catch (e) {}
            updateRouteIfReady();
            emitProgressToFlutter();
            try { applyToFlutter(); } catch (e2) {}
          });
          try { fitToPoints([pickup[0], pickup[1]], [dropoff[0], dropoff[1]]); } catch (e3) {}
          return;
        }
        var moveAS = pickupCloserThanDropoffCoords(c);
        if (moveAS) {
          pickup = [c[0], c[1], query];
          ensurePlacemarkA(c);
        } else {
          dropoff = [c[0], c[1], query];
          ensurePlacemarkB(c);
        }
        setHint('Точки обновлены.');
        emitProgressToFlutter();
        geocode(c, function (addr2) {
          try {
            if (moveAS) pickup[2] = addr2 || query;
            else dropoff[2] = addr2 || query;
          } catch (e4) {}
          updateRouteIfReady();
          emitProgressToFlutter();
          try { applyToFlutter(); } catch (e5) {}
        });
        try { fitToPoints([pickup[0], pickup[1]], [dropoff[0], dropoff[1]]); } catch (e6) {}
      });
    });
  } catch (err) {
    console.warn('SuggestView', err);
  }

  map.events.add('click', function (e) {
    if (MAP_MODE === 'route_display_only') return;
    var c = e.get('coords');
    if (searchPlacemark) {
      try { map.geoObjects.remove(searchPlacemark); } catch (x) {}
      searchPlacemark = null;
    }
    if (MAP_MODE === 'pickup_only') {
      pickup = [c[0], c[1], ''];
      if (placemarkA) map.geoObjects.remove(placemarkA);
      placemarkA = new ymaps.Placemark(c, { balloonContent: 'Откуда' }, { preset: 'islands#darkOrangeDotIcon' });
      map.geoObjects.add(placemarkA);
      if (placemarkB) { try { map.geoObjects.remove(placemarkB); } catch (x) {} placemarkB = null; }
      dropoff = null;
      clearRoute();
      updateRouteIfReady();
      geocode(c, function (addr) {
        pickup[2] = addr;
        setHint('Точка посадки выбрана.');
        emitProgressToFlutter();
        try { applyPartialPickupToFlutter(); } catch (ex) {}
      });
      emitProgressToFlutter();
      return;
    }
    if (MAP_MODE === 'dropoff_only') {
      if (!pickup) {
        setHint('Сначала выберите точку посадки в приложении.');
        return;
      }
      dropoff = [c[0], c[1], ''];
      if (placemarkB) map.geoObjects.remove(placemarkB);
      placemarkB = new ymaps.Placemark(c, { balloonContent: 'Куда' }, { preset: 'islands#redDotIcon' });
      map.geoObjects.add(placemarkB);
      geocode(c, function (addr) {
        dropoff[2] = addr;
        setHint('Пункт назначения выбран.');
        updateRouteIfReady();
        emitProgressToFlutter();
        try { applyPartialDropoffToFlutter(); } catch (e) {}
      });
      emitProgressToFlutter();
      return;
    }
    if (!pickup) {
      pickup = [c[0], c[1], ''];
      if (placemarkA) map.geoObjects.remove(placemarkA);
      placemarkA = new ymaps.Placemark(c, { balloonContent: 'Откуда' }, { preset: 'islands#darkOrangeDotIcon' });
      map.geoObjects.add(placemarkA);
      updateRouteIfReady();
      geocode(c, function (addr) {
        pickup[2] = addr;
        setHint('Теперь укажите куда (второй клик).');
        emitProgressToFlutter();
      });
      emitProgressToFlutter();
    } else if (!dropoff) {
      dropoff = [c[0], c[1], ''];
      if (placemarkB) map.geoObjects.remove(placemarkB);
      placemarkB = new ymaps.Placemark(c, { balloonContent: 'Куда' }, { preset: 'islands#redDotIcon' });
      map.geoObjects.add(placemarkB);
      geocode(c, function (addr) {
        dropoff[2] = addr;
        setHint('Точки выбраны.');
        updateRouteIfReady();
        emitProgressToFlutter();
        try { applyToFlutter(); } catch (e2) {}
      });
      emitProgressToFlutter();
    } else {
      var moveAclick = pickupCloserThanDropoffCoords(c);
      if (moveAclick) {
        pickup = [c[0], c[1], ''];
        ensurePlacemarkA(c);
      } else {
        dropoff = [c[0], c[1], ''];
        ensurePlacemarkB(c);
      }
      geocode(c, function (addr) {
        if (moveAclick) pickup[2] = addr;
        else dropoff[2] = addr;
        setHint('Точки обновлены.');
        updateRouteIfReady();
        emitProgressToFlutter();
        try { applyToFlutter(); } catch (e2) {}
      });
      emitProgressToFlutter();
      try { fitToPoints([pickup[0], pickup[1]], [dropoff[0], dropoff[1]]); } catch (e3) {}
    }
  });

  flushDeferredMapCommands();
});
</script>
</body>
</html>
''';
}

/// Мост для WebView: только `toFlutter` (остальное — общий скрипт выше).
const String yandexMapBridgeWebView = '''
function toFlutter(payload) {
  InvoYandexMap.postMessage(payload);
}
''';

/// Мост для iframe: только `toFlutter` (слушатель `message` — в общем скрипте).
const String yandexMapBridgeIframe = '''
function toFlutter(payload) {
  if (window.parent && window.parent !== window) {
    window.parent.postMessage('invo_yandex:' + payload, '*');
  }
}
''';
