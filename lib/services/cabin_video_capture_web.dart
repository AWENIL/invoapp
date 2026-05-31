// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:camera/camera.dart';

import 'cabin_recording_settings.dart';
import 'cabin_video_capture.dart';

Future<CabinVideoCapture> createCabinVideoCapture() async => WebCabinVideoCapture();

class WebCabinVideoRecorder {
  html.MediaStream? _stream;
  html.MediaRecorder? _recorder;
  final List<html.Blob> _chunks = [];
  Completer<XFile?>? _stopCompleter;
  String _mimeType = 'video/webm';

  bool get isRecording => _recorder?.state == 'recording';

  Future<bool> prepare() async {
    await dispose();
    _mimeType = _pickMimeType();
    final media = html.window.navigator.mediaDevices;
    if (media == null) return false;

    try {
      _stream = await media.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 320},
          'height': {'ideal': 240},
          'frameRate': {
            'ideal': CabinRecordingSettings.fps,
            'max': CabinRecordingSettings.maxFps,
          },
        },
      });
    } catch (_) {
      // Попытка без facingMode (fallback для камер без front-facing).
      try {
        _stream = await media.getUserMedia({'audio': false, 'video': true});
      } catch (_) {
        return false;
      }
    }
    return _stream != null;
  }

  Future<void> startRecording() async {
    final stream = _stream;
    if (stream == null) {
      throw StateError('Камера не инициализирована');
    }

    _chunks.clear();
    _recorder = html.MediaRecorder(stream, {
      'mimeType': _mimeType,
      'videoBitsPerSecond': CabinRecordingSettings.videoBitrate,
    });

    _stopCompleter = Completer<XFile?>();
    _recorder!.addEventListener('dataavailable', (html.Event event) {
      final blobEvent = event as html.BlobEvent;
      final data = blobEvent.data;
      if (data != null && data.size > 0) {
        _chunks.add(data);
      }
    });
    _recorder!.addEventListener('stop', (_) {
      unawaited(_completeRecording());
    });

    _recorder!.start();
  }

  Future<void> _completeRecording() async {
    final completer = _stopCompleter;
    if (completer == null || completer.isCompleted) return;

    try {
      if (_chunks.isEmpty) {
        completer.complete(null);
        return;
      }
      final blob = html.Blob(_chunks, _mimeType);
      final reader = html.FileReader();
      final loadFuture = reader.onLoad.first;
      reader.readAsArrayBuffer(blob);
      await loadFuture;
      final result = reader.result;
      if (result is! ByteBuffer) {
        completer.complete(null);
        return;
      }
      final bytes = Uint8List.view(result);
      completer.complete(
        XFile.fromData(
          bytes,
          name: _fileNameForMime(_mimeType),
          mimeType: _mimeType,
        ),
      );
    } catch (_) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
  }

  Future<XFile?> stopRecording() async {
    final recorder = _recorder;
    final completer = _stopCompleter;
    if (recorder == null || completer == null) return null;
    if (recorder.state != 'inactive') {
      recorder.stop();
    }
    try {
      return await completer.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      return null;
    }
  }

  Future<void> dispose() async {
    final recorder = _recorder;
    if (recorder != null && recorder.state == 'recording') {
      try {
        recorder.stop();
      } catch (_) {
        // ignore
      }
    }
    _recorder = null;
    _stopCompleter = null;
    _chunks.clear();

    final stream = _stream;
    _stream = null;
    stream?.getTracks().forEach((track) => track.stop());
  }

  static String _pickMimeType() {
    const candidates = [
      'video/webm;codecs=vp8',
      'video/webm',
      'video/mp4',
    ];
    for (final type in candidates) {
      if (html.MediaRecorder.isTypeSupported(type)) {
        return type;
      }
    }
    return 'video/webm';
  }

  static String _fileNameForMime(String mimeType) {
    if (mimeType.contains('mp4')) return 'recording.mp4';
    return 'recording.webm';
  }
}

class WebCabinVideoCapture implements CabinVideoCapture {
  final WebCabinVideoRecorder _recorder = WebCabinVideoRecorder();

  @override
  bool get isRecording => _recorder.isRecording;

  @override
  Future<bool> prepare() => _recorder.prepare();

  @override
  Future<void> startRecording() => _recorder.startRecording();

  @override
  Future<XFile?> stopRecording() => _recorder.stopRecording();

  @override
  Future<void> dispose() => _recorder.dispose();
}
