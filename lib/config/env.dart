export 'package:invo_common/invo_common.dart' show yandexMapsApiKey;

/// Базовый URL API без завершающего слэша.
///
/// По умолчанию — продакшен. Локально: `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000`
/// Android-эмулятор к хосту: `--dart-define=API_BASE_URL=http://10.0.2.2:8000`
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.invotaxi.ukudarov.pro',
);

/// Юридические документы: `--dart-define=TERMS_URL=...` и `PRIVACY_URL=...`
const String termsUrl = String.fromEnvironment('TERMS_URL', defaultValue: '');
const String privacyUrl = String.fromEnvironment('PRIVACY_URL', defaultValue: '');

/// Телефон диспетчера для экрана поддержки: `--dart-define=DISPATCH_PHONE_TEL=tel:+77271234567`
const String dispatchPhoneTelUri = String.fromEnvironment(
  'DISPATCH_PHONE_TEL',
  defaultValue: '',
);

/// С завершающим `/`, иначе Dio склеивает `.../mobile` + `auth/...` → `.../mobileauth/...`
String get mobileApiPrefix => '$apiBaseUrl/api/mobile/';

/// JWT в query: `?token=`. Путь `/ws/...` без `/api`.
String get wsBaseUrl {
  final u = apiBaseUrl.trim();
  if (u.startsWith('https://')) {
    return 'wss://${u.substring(8)}';
  }
  if (u.startsWith('http://')) {
    return 'ws://${u.substring(7)}';
  }
  return 'ws://$u';
}
