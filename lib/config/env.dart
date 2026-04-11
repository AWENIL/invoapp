/// Базовый URL API без завершающего слэша.
///
/// По умолчанию — продакшен. Локально: `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000`
/// Android-эмулятор к хосту: `--dart-define=API_BASE_URL=http://10.0.2.2:8000`
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.invotaxi.ukudarov.pro',
);

/// С завершающим `/`, иначе Dio склеивает `.../mobile` + `auth/...` → `.../mobileauth/...`
String get mobileApiPrefix => '$apiBaseUrl/api/mobile/';

/// Необязательно: `flutter run --dart-define=DISPATCH_PHONE_TEL=tel:+77271234567`
const String dispatchPhoneTelUri = String.fromEnvironment(
  'DISPATCH_PHONE_TEL',
  defaultValue: '',
);
