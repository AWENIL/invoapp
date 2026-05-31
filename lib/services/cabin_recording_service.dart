import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../api/invo_api.dart';
import 'cabin_recording_settings.dart';
import 'cabin_video_capture.dart';

export 'cabin_recording_settings.dart';

/// Парсит карту заказа из ответа active-order или локального контекста.
Map<String, dynamic>? orderMapFromActiveResponse(Map<String, dynamic>? activeOrder) {
  if (activeOrder == null) return null;
  final nested = activeOrder['order'];
  if (nested is Map) return Map<String, dynamic>.from(nested);
  return activeOrder;
}

/// Запись салона с камеры во время статуса ride_ongoing (web + mobile).
class CabinRecordingService extends ChangeNotifier {
  CabinRecordingService(
    this._api, {
    /// Фабрика capture — переопределяется в тестах.
    Future<CabinVideoCapture> Function()? captureFactory,
  }) : _captureFactory = captureFactory ?? createCabinVideoCapture;

  final InvoApi _api;
  final Future<CabinVideoCapture> Function() _captureFactory;
  CabinVideoCapture? _capture;
  String? _activeOrderId;
  bool _starting = false;
  bool _rotateBusy = false;
  Timer? _segmentTimer;
  int _nextSegmentIndex = 0;

  /// Ошибки только для камеры/инфраструктуры; транзиентные сетевые — не пишутся.
  String? lastError;

  bool get isRecording => _activeOrderId != null && (_capture?.isRecording ?? false);

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
      // Уже записываем этот заказ (или стартуем) — всё хорошо.
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
    // Конкурентный вызов во время старта того же заказа — оптимистично true.
    if (_starting) return true;
    if (_activeOrderId == orderId && isRecording) {
      return true;
    }

    _starting = true;
    lastError = null;
    try {
      await _stop(finishOnServer: false);

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

      // Сообщаем серверу — ошибки статуса игнорируем (идемпотентный вызов).
      try {
        await _api.startCabinRecording(orderId);
      } catch (_) {
        // Запись уже начата или заказ завершился — продолжаем локально.
      }

      _activeOrderId = orderId;
      _capture = capture;
      _nextSegmentIndex = 0;

      await capture.startRecording();
      _segmentTimer?.cancel();
      _segmentTimer = Timer.periodic(CabinRecordingSettings.segmentDuration, (_) {
        unawaited(_rotateSegment());
      });
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
        // Загружаем в фоне — ошибки сети не блокируют камеру и не идут в lastError.
        unawaited(_uploadSegmentSilent(orderId, index, file));
      }

      // Перезапускаем только если _stop не очистил capture под нами.
      if (_activeOrderId == orderId && _capture == capture) {
        await capture.startRecording();
      }
    } catch (e) {
      // Ошибки поворота сегмента не пишем в lastError — не тревожим UI.
    } finally {
      _rotateBusy = false;
    }
  }

  Future<void> _uploadSegmentSilent(String orderId, int index, XFile file) async {
    try {
      await _api.uploadCabinSegment(orderId, index, file);
    } catch (_) {
      // Транзиентные ошибки (сеть, статус заказа изменился) — игнорируем тихо.
    }
  }

  Future<void> _stop({bool finishOnServer = true}) async {
    final orderId = _activeOrderId;
    _activeOrderId = null;
    _segmentTimer?.cancel();
    _segmentTimer = null;

    // Обнуляем _capture ДО await, чтобы _rotateSegment увидел null и не перезапустил запись.
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

  @override
  void dispose() {
    // Синхронно очищаем таймер и capture, не вызывая notifyListeners после dispose.
    _activeOrderId = null;
    _segmentTimer?.cancel();
    _segmentTimer = null;
    final capture = _capture;
    _capture = null;
    if (capture != null) {
      capture.dispose().ignore();
    }
    super.dispose();
  }
}
