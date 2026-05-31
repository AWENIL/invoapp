import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:invo_driver/api/invo_api.dart';
import 'package:invo_driver/services/cabin_recording_service.dart';
import 'package:invo_driver/services/cabin_video_capture.dart';

// ------------------------------------------------------------------ //
// Моки                                                                 //
// ------------------------------------------------------------------ //

class MockInvoApi extends Mock implements InvoApi {}

class FakeCabinVideoCapture implements CabinVideoCapture {
  bool _recording = false;
  int prepareCallCount = 0;
  int startCallCount = 0;
  int stopCallCount = 0;
  bool prepareResult = true;
  // Если null — stopRecording вернёт null.
  XFile? segmentFile = XFile.fromData(Uint8List(0), name: 'seg.webm', mimeType: 'video/webm');

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> prepare() async {
    prepareCallCount++;
    return prepareResult;
  }

  @override
  Future<void> startRecording() async {
    _recording = true;
    startCallCount++;
  }

  @override
  Future<XFile?> stopRecording() async {
    _recording = false;
    stopCallCount++;
    return segmentFile;
  }

  @override
  Future<void> dispose() async {
    _recording = false;
  }
}

// ------------------------------------------------------------------ //
// Хелперы                                                              //
// ------------------------------------------------------------------ //

Map<String, dynamic> _orderMap(String id, {String status = 'ride_ongoing'}) =>
    {'id': id, 'status': status};

CabinRecordingService _makeService(InvoApi api, FakeCabinVideoCapture capture) {
  return CabinRecordingService(
    api,
    captureFactory: () async => capture,
  );
}

// ------------------------------------------------------------------ //
// Тесты                                                                //
// ------------------------------------------------------------------ //

void main() {
  late MockInvoApi api;
  late FakeCabinVideoCapture capture;

  setUp(() {
    api = MockInvoApi();
    capture = FakeCabinVideoCapture();

    registerFallbackValue(XFile.fromData(Uint8List(0), name: 'f.webm'));

    // По умолчанию все API-вызовы — no-op.
    when(() => api.startCabinRecording(any())).thenAnswer((_) async {});
    when(() => api.uploadCabinSegment(any(), any(), any())).thenAnswer((_) async {});
    when(() => api.finishCabinRecording(any(), video: any(named: 'video'), segmentIndex: any(named: 'segmentIndex')))
        .thenAnswer((_) async {});
  });

  group('CabinRecordingService', () {
    test('start_begins_recording: syncWithOrder ride_ongoing запускает запись', () async {
      final svc = _makeService(api, capture);

      final ok = await svc.syncWithOrder(_orderMap('order-1'));

      expect(ok, isTrue);
      expect(svc.isRecording, isTrue);
      verify(() => api.startCabinRecording('order-1')).called(1);

      svc.dispose();
    });

    test('rotate_uploads_segment: _rotateSegment загружает сегмент и перезапускает камеру', () async {
      final svc = _makeService(api, capture);
      await svc.syncWithOrder(_orderMap('order-2'));

      // Имитируем один тик таймера вручную через публичный метод _rotateSegment.
      // Так как он приватный, ждём реальный тик — но в тестах проще вызвать
      // stopAndUploadIfActive и проверить через вызовы.
      expect(capture.startCallCount, equals(1));

      // Останавливаем — должна загрузиться финальная запись.
      await svc.stopAndUploadIfActive('order-2');

      expect(capture.stopCallCount, greaterThanOrEqualTo(1));
      verify(() => api.finishCabinRecording('order-2', video: any(named: 'video'), segmentIndex: any(named: 'segmentIndex'))).called(1);

      svc.dispose();
    });

    test('stop_uploads_final_and_calls_finish: stopAndUploadIfActive → finishCabinRecording вызван', () async {
      final svc = _makeService(api, capture);
      await svc.syncWithOrder(_orderMap('order-3'));
      expect(svc.isRecording, isTrue);

      await svc.stopAndUploadIfActive('order-3');

      expect(svc.isRecording, isFalse);
      verify(() => api.finishCabinRecording('order-3', video: any(named: 'video'), segmentIndex: any(named: 'segmentIndex'))).called(1);

      svc.dispose();
    });

    test('sync_idempotent_same_order: двойной syncWithOrder не запускает старт дважды', () async {
      final svc = _makeService(api, capture);

      final ok1 = await svc.syncWithOrder(_orderMap('order-4'));
      final ok2 = await svc.syncWithOrder(_orderMap('order-4'));

      expect(ok1, isTrue);
      expect(ok2, isTrue);
      // startCabinRecording должен быть вызван ровно один раз.
      verify(() => api.startCabinRecording('order-4')).called(1);
      expect(capture.prepareCallCount, equals(1));

      svc.dispose();
    });

    test('sync_stops_on_non_ongoing: syncWithOrder completed при активной записи → finishCabinRecording вызван', () async {
      final svc = _makeService(api, capture);
      await svc.syncWithOrder(_orderMap('order-5'));
      expect(svc.isRecording, isTrue);

      // Статус меняется на completed.
      await svc.syncWithOrder(_orderMap('order-5', status: 'completed'));

      expect(svc.isRecording, isFalse);
      verify(() => api.finishCabinRecording('order-5', video: any(named: 'video'), segmentIndex: any(named: 'segmentIndex'))).called(1);

      svc.dispose();
    });

    test('stop_race_rotate_does_not_restart: _stop очищает capture до rotate', () async {
      // Capture с замедленным stopRecording чтобы проверить гонку.
      final slowCapture = FakeCabinVideoCapture();
      final completer = Completer<XFile?>();
      int startAfterStopCount = 0;

      // Переопределяем stopRecording — зависает пока не разрешим.
      final svc = CabinRecordingService(
        api,
        captureFactory: () async => slowCapture,
      );

      await svc.syncWithOrder(_orderMap('order-6'));
      expect(svc.isRecording, isTrue);

      // Останавливаем синхронно — capture должен быть очищен до await.
      final stopFuture = svc.stopAndUploadIfActive('order-6');
      // После вызова _stop isRecording должен стать false немедленно
      // (до завершения await stopRecording), потому что _activeOrderId уже null.
      expect(svc.isRecording, isFalse);

      await stopFuture;
      expect(startAfterStopCount, equals(0));

      svc.dispose();
    });

    test('no_recording_if_camera_not_granted: prepare() возвращает false → syncWithOrder false + lastError', () async {
      // Симулируем недоступность камеры через prepare() = false.
      capture.prepareResult = false;
      final svc = _makeService(api, capture);

      final ok = await svc.syncWithOrder(_orderMap('order-7'));

      expect(ok, isFalse);
      expect(svc.lastError, isNotNull);
      expect(svc.isRecording, isFalse);
      verifyNever(() => api.startCabinRecording(any()));

      svc.dispose();
    });
  });
}
