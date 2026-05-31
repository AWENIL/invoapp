// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'driver_camera_permission.dart';

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
  final state = await getCameraAccessState();
  return state == CameraAccessState.granted;
}

Future<bool> ensureCameraGranted() async {
  final mediaDevices = html.window.navigator.mediaDevices;
  if (mediaDevices == null) return false;

  html.MediaStream stream;
  try {
    stream = await mediaDevices.getUserMedia({'video': true, 'audio': false});
  } catch (_) {
    try {
      stream = await mediaDevices.getUserMedia({
        'video': {'facingMode': 'user'},
        'audio': false,
      });
    } catch (_) {
      return false;
    }
  }

  stream.getTracks().forEach((track) => track.stop());
  return true;
}
