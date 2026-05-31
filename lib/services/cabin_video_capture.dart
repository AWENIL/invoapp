import 'package:camera/camera.dart';

import 'cabin_video_capture_impl.dart'
    if (dart.library.html) 'cabin_video_capture_web.dart'
    if (dart.library.io) 'cabin_video_capture_mobile.dart' as impl;

/// Платформенный захват видео для записи салона.
abstract class CabinVideoCapture {
  Future<bool> prepare();

  Future<void> startRecording();

  Future<XFile?> stopRecording();

  Future<void> dispose();

  bool get isRecording;
}

Future<CabinVideoCapture> createCabinVideoCapture() => impl.createCabinVideoCapture();
