import 'camera_permission_impl.dart'
    if (dart.library.html) 'camera_permission_web.dart' as impl;

/// Состояние доступа к камере.
enum CameraAccessState { granted, denied, prompt, unknown }

abstract final class DriverCameraPermission {
  static Future<CameraAccessState> accessState() => impl.getCameraAccessState();

  /// Проверка без запроса диалога (Permissions API / permission_handler).
  static Future<bool> isGranted() async {
    final state = await accessState();
    return state == CameraAccessState.granted;
  }

  /// Запрос доступа — вызывать только по нажатию кнопки (user gesture на web).
  static Future<bool> ensureGranted() => impl.ensureCameraGranted();
}
