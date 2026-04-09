/// Базовый URL API без завершающего слэша.
/// Локально: `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000`
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.invotaxi.ukudarov.pro',
);

String get mobileApiPrefix => '$apiBaseUrl/api/mobile';
