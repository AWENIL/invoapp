import 'package:permission_handler/permission_handler.dart';

import 'driver_camera_permission.dart';

Future<CameraAccessState> getCameraAccessState() async {
  final status = await Permission.camera.status;
  if (status.isGranted) return CameraAccessState.granted;
  if (status.isPermanentlyDenied || status.isRestricted) {
    return CameraAccessState.denied;
  }
  return CameraAccessState.prompt;
}

Future<bool> isCameraGranted() async {
  return await getCameraAccessState() == CameraAccessState.granted;
}

Future<bool> ensureCameraGranted() async {
  var status = await Permission.camera.status;
  if (!status.isGranted) {
    status = await Permission.camera.request();
  }
  return status.isGranted;
}
