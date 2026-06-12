// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'driver_camera_permission.dart';
import 'web_camera_session.dart';

Future<CameraAccessState> getCameraAccessState() async {
  try {
    final permissions = html.window.navigator.permissions;
    if (permissions != null) {
      final status = await permissions.query({'name': 'camera'});
      switch (status.state) {
        case 'granted':
          return CameraAccessState.granted;
        case 'denied':
          return CameraAccessState.denied;
        case 'prompt':
          return CameraAccessState.prompt;
      }
    }
  } catch (_) {
    // Permissions API недоступен — проверим через getUserMedia ниже.
  }
  return CameraAccessState.unknown;
}

Future<bool> isCameraGranted() async {
  if (WebCameraSession.isActive) return true;
  final state = await getCameraAccessState();
  return state == CameraAccessState.granted;
}

Future<bool> ensureCameraGranted() async {
  // Оставляем stream открытым — prepare() переиспользует его после PATCH.
  return WebCameraSession.acquire();
}
