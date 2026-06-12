/// Заглушка для mobile — сессия камеры только на web.
abstract final class WebCameraSession {
  static bool get isActive => false;

  static Object? get stream => null;

  static Future<bool> acquire() async => true;

  static void release() {}
}
