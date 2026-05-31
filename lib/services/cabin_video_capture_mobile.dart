import 'package:camera/camera.dart';

import 'cabin_recording_settings.dart';import 'cabin_video_capture.dart';

Future<CabinVideoCapture> createCabinVideoCapture() async => MobileCabinVideoCapture();

class MobileCabinVideoCapture implements CabinVideoCapture {
  CameraController? _controller;

  @override
  bool get isRecording => _controller?.value.isRecordingVideo ?? false;

  @override
  Future<bool> prepare() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return false;

    CameraDescription selected;
    CameraDescription? front;
    for (final c in cameras) {
      if (c.lensDirection == CameraLensDirection.front) {
        front = c;
        break;
      }
    }
    selected = front ?? cameras.first;

    await dispose();
    final ctrl = CameraController(
      selected,
      CabinRecordingSettings.resolution,
      enableAudio: false,
      fps: CabinRecordingSettings.fps,
      videoBitrate: CabinRecordingSettings.videoBitrate,
    );
    await ctrl.initialize();
    _controller = ctrl;
    return true;
  }

  @override
  Future<void> startRecording() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      throw StateError('Камера не инициализирована');
    }
    await ctrl.startVideoRecording(enablePersistentRecording: true);
  }

  @override
  Future<XFile?> stopRecording() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || !ctrl.value.isRecordingVideo) {
      return null;
    }
    return ctrl.stopVideoRecording();
  }

  @override
  Future<void> dispose() async {
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      try {
        await ctrl.dispose();
      } catch (_) {
        // ignore dispose errors
      }
    }
  }
}
