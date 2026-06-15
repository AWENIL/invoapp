import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../api/invo_api.dart';
import 'cabin_recording_settings.dart';
import 'cabin_video_capture.dart';
import 'web_camera_session.dart';

export 'cabin_recording_settings.dart';

/// Парсит карту заказа из ответа active-order или локального контекста.
Map<String, dynamic>? orderMapFromActiveResponse(Map<String, dynamic>? activeOrder) {
  if (activeOrder == null) return null;
  final nested = activeOrder['order'];
  if (nested is Map) return Map<String, dynamic>.from(nested);
  return activeOrder;
}

class _PendingUpload {
  const _PendingUpload({
    required this.orderId,
    required this.index,
    required this.file,
  });

  final String orderId;
  final int index;
  final XFile file;
}

/// Запись салона с камеры во время статуса ride_ongoing (web + mobile).
class CabinRecordingService extends ChangeNotifier {
  CabinRecordingService(
    this._api, {
    /// Фабрика capture — переопределяется в тестах.
    Future<CabinVideoCapture> Function()? captureFactory,
    /// Интервал watchdog — переопределяется в тестах.
    Duration? watchdogInterval,
  })  : _captureFactory = captureFactory ?? createCabinVideoCapture,
        _watchdogInterval = watchdogInterval ?? const Duration(seconds: 5);

  final InvoApi _api;
  final Future<CabinVideoCapture> Function() _captureFactory;
  final Duration _watchdogInterval;
  CabinVideoCapture? _capture;
  String? _activeOrderId;
  bool _starting = false;
  bool _rotateBusy = false;
  Timer? _segmentTimer;
  Timer? _watchdogTimer;
  int _nextSegmentIndex = 0;
  DateTime? _recordingInactiveSince;

  final List<_PendingUpload> _uploadQueue = [];
  bool _uploadWorkerRunning = false;
  int _pendingUploads = 0;
  int _failedUploads = 0;

  /// Ошибки только для камеры/инфраструктуры; транзиентные сетевые — не пишутся.
  String? lastError;

  bool get isRecording => _activeOrderId != null && (_capture?.isRecording ?? false);

  int get pendingUploads => _pendingUploads;

  int get failedUploads => _failedUploads;

  static bool get platformSupportsRecording {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Останавливает запись и загружает видео на сервер (перед сменой статуса поездки).
  Future<void> stopAndUploadIfActive([String? orderId]) async {
    if (_activeOrderId == null) return;
    if (orderId != null && _activeOrderId != orderId) return;
    await _stop(finishOnServer: true);
  }

  /// Синхронизация с активным заказом. Возвращает true, если запись идёт.
  Future<bool> syncWithOrder(Map<String, dynamic>? activeOrder) async {
    if (!platformSupportsRecording) return false;

    final orderMap = orderMapFromActiveResponse(activeOrder);
    final orderId = orderMap?['id']?.toString();
    final status = orderMap?['status']?.toString() ?? '';

    if (orderId != null && status == 'ride_ongoing') {
      if (_activeOrderId == orderId && (isRecording || _starting)) {
        return true;
      }
      return _start(orderId);
    }

    if (_activeOrderId != null) {
      await _stop();
    }
    return false;
  }

  Future<bool> _start(String orderId) async {
    if (_starting) return true;
    if (_activeOrderId == orderId && isRecording) {
      return true;
    }

    _starting = true;
    lastError = null;
    try {
      await _stop(finishOnServer: false, releaseCameraSession: false);

      final capture = await _captureFactory();
      final bool prepared;
      try {
        prepared = await capture.prepare();
      } catch (e) {
        await capture.dispose();
        lastError = 'Не удалось открыть камеру: $e';
        return false;
      }

      if (!prepared) {
        await capture.dispose();
        lastError = 'Камера недоступна. Разрешите доступ к камере в настройках браузера.';
        return false;
      }

      try {
        await _api.startCabinRecording(orderId);
      } catch (_) {
        // Запись уже начата или заказ завершился — продолжаем локально.
      }

      _activeOrderId = orderId;
      _capture = capture;
      _nextSegmentIndex = 0;
      _recordingInactiveSince = null;

      await capture.startRecording();
      _segmentTimer?.cancel();
      _segmentTimer = Timer.periodic(CabinRecordingSettings.segmentDuration, (_) {
        unawaited(_rotateSegment());
      });
      _startWatchdog();
      notifyListeners();
      return true;
    } catch (e) {
      lastError = e.toString();
      await _disposeCapture();
      _activeOrderId = null;
      notifyListeners();
      return false;
    } finally {
      _starting = false;
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) {
      unawaited(_watchdogTick());
    });
  }

  Future<void> _watchdogTick() async {
    if (_activeOrderId == null || _starting || _rotateBusy) return;

    if (isRecording) {
      _recordingInactiveSince = null;
      return;
    }

    _recordingInactiveSince ??= DateTime.now();
    if (DateTime.now().difference(_recordingInactiveSince!) >= _watchdogInterval) {
      await _recoverRecording();
    }
  }

  Future<void> _recoverRecording() async {
    if (_activeOrderId == null) return;

    try {
      await _disposeCapture();
      final capture = await _captureFactory();
      final prepared = await capture.prepare();
      if (!prepared) {
        lastError = 'Камера недоступна при восстановлении записи';
        notifyListeners();
        return;
      }

      _capture = capture;
      await capture.startRecording();
      _recordingInactiveSince = null;
      notifyListeners();
    } catch (e) {
      lastError = 'Не удалось восстановить запись: $e';
      notifyListeners();
    }
  }

  Future<void> _rotateSegment() async {
    if (_rotateBusy || _activeOrderId == null) return;
    final orderId = _activeOrderId!;
    final capture = _capture;
    if (capture == null || !capture.isRecording) return;

    _rotateBusy = true;
    try {
      final index = _nextSegmentIndex;
      final file = await capture.stopRecording();
      _nextSegmentIndex++;

      if (file != null) {
        _enqueueUpload(orderId, index, file);
      }

      if (_activeOrderId == orderId && _capture == capture) {
        try {
          await capture.startRecording();
          _recordingInactiveSince = null;
        } catch (_) {
          await _recoverRecording();
        }
      }
    } catch (_) {
      await _recoverRecording();
    } finally {
      _rotateBusy = false;
    }
  }

  void _enqueueUpload(String orderId, int index, XFile file) {
    _uploadQueue.add(_PendingUpload(orderId: orderId, index: index, file: file));
    _pendingUploads++;
    notifyListeners();
    unawaited(_processUploadQueue());
  }

  Future<void> _processUploadQueue() async {
    if (_uploadWorkerRunning) return;
    _uploadWorkerRunning = true;

    const retryDelays = [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ];

    while (_uploadQueue.isNotEmpty) {
      final item = _uploadQueue.removeAt(0);
      var uploaded = false;

      for (var attempt = 0; attempt < retryDelays.length; attempt++) {
        try {
          await _api.uploadCabinSegment(item.orderId, item.index, item.file);
          uploaded = true;
          break;
        } catch (_) {
          if (attempt < retryDelays.length - 1) {
            await Future<void>.delayed(retryDelays[attempt]);
          }
        }
      }

      _pendingUploads--;
      if (!uploaded) {
        _failedUploads++;
        lastError = 'Сегмент ${item.index} не загружен';
      }
      notifyListeners();
    }

    _uploadWorkerRunning = false;
  }

  Future<void> _stop({bool finishOnServer = true, bool releaseCameraSession = true}) async {
    final orderId = _activeOrderId;
    _activeOrderId = null;
    _segmentTimer?.cancel();
    _segmentTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _recordingInactiveSince = null;

    final capture = _capture;
    _capture = null;
    XFile? video;
    final finalIndex = _nextSegmentIndex;
    if (capture != null && capture.isRecording) {
      try {
        video = await capture.stopRecording();
      } catch (_) {
        // ignore stop errors
      }
    }

    if (capture != null) {
      try {
        await capture.dispose();
      } catch (_) {
        // ignore
      }
    }

    if (kIsWeb && releaseCameraSession) {
      WebCameraSession.release();
    }

    notifyListeners();

    if (finishOnServer && orderId != null) {
      try {
        await _api.finishCabinRecording(
          orderId,
          video: video,
          segmentIndex: video != null ? finalIndex : null,
        );
      } catch (_) {
        // Ошибки finish — игнорируем (заказ мог уже завершиться).
      }
    }
  }

  Future<void> _disposeCapture() async {
    final capture = _capture;
    _capture = null;
    if (capture != null) {
      try {
        await capture.dispose();
      } catch (_) {
        // ignore dispose errors
      }
    }
  }

  @visibleForTesting
  Future<void> rotateSegmentForTest() => _rotateSegment();

  @override
  void dispose() {
    _activeOrderId = null;
    _segmentTimer?.cancel();
    _segmentTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    final capture = _capture;
    _capture = null;
    if (capture != null) {
      capture.dispose().ignore();
    }
    if (kIsWeb) {
      WebCameraSession.release();
    }
    super.dispose();
  }
}
