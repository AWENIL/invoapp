// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'cabin_recording_settings.dart';

/// Держит MediaStream между ensureGranted (user gesture) и записью.
abstract final class WebCameraSession {
  static html.MediaStream? _stream;

  static html.MediaStream? get stream => _stream;

  static bool get isActive {
    final s = _stream;
    if (s == null) return false;
    final tracks = s.getVideoTracks();
    return tracks.isNotEmpty && tracks.first.readyState == 'live';
  }

  static bool _isMobileWeb() {
    final ua = html.window.navigator.userAgent.toLowerCase();
    return ua.contains('mobile') ||
        ua.contains('android') ||
        ua.contains('iphone') ||
        ua.contains('ipad');
  }

  static Object _lightVideoConstraints({bool preferFront = false}) {
    if (preferFront && _isMobileWeb()) {
      return {
        'facingMode': 'user',
        'width': {'ideal': 320},
        'height': {'ideal': 240},
        'frameRate': {
          'ideal': CabinRecordingSettings.fps,
          'max': CabinRecordingSettings.maxFps,
        },
      };
    }
    return {
      'width': {'ideal': 320},
      'height': {'ideal': 240},
      'frameRate': {
        'ideal': CabinRecordingSettings.fps,
        'max': CabinRecordingSettings.maxFps,
      },
    };
  }

  /// Открывает камеру и оставляет stream активным до release().
  static Future<bool> acquire() async {
    if (isActive) return true;
    release();

    final media = html.window.navigator.mediaDevices;
    if (media == null) return false;

    try {
      _stream = await media.getUserMedia({'audio': false, 'video': true});
    } catch (_) {
      try {
        _stream = await media.getUserMedia({
          'audio': false,
          'video': _lightVideoConstraints(preferFront: true),
        });
      } catch (_) {
        try {
          _stream = await media.getUserMedia({'audio': false, 'video': true});
        } catch (_) {
          return false;
        }
      }
    }
    return _stream != null;
  }

  static void release() {
    final s = _stream;
    _stream = null;
    s?.getTracks().forEach((track) => track.stop());
  }
}
