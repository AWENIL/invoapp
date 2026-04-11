/// Ссылки на маршруты Яндекс.Карт (https).
Uri yandexMapsRouteBetween({
  required double fromLat,
  required double fromLon,
  required double toLat,
  required double toLon,
}) {
  return Uri.parse(
    'https://yandex.ru/maps/?mode=routes&rtext=$fromLat,$fromLon~$toLat,$toLon',
  );
}

/// Маршрут «от текущего места» до точки (Яндекс подставляет старт в приложении).
Uri yandexMapsRouteToPointOnly({
  required double toLat,
  required double toLon,
}) {
  return Uri.parse('https://yandex.ru/maps/?mode=routes&rtext=~$toLat,$toLon');
}
