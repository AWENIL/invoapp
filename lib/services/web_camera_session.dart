import 'web_camera_session_stub.dart'
    if (dart.library.html) 'web_camera_session_web.dart' as impl;

/// Фасад для платформенной сессии камеры (web — живой MediaStream).
abstract final class WebCameraSession {
  static bool get isActive => impl.WebCameraSession.isActive;

  static Object? get stream => impl.WebCameraSession.stream;

  static Future<bool> acquire() => impl.WebCameraSession.acquire();

  static void release() => impl.WebCameraSession.release();
}
