import 'package:camera/camera.dart';

/// Параметры записи салона: минимальная нагрузка на CPU, память и сеть.
abstract final class CabinRecordingSettings {
  /// Достаточно для обзора салона, заметно легче medium/high.
  static const resolution = ResolutionPreset.low;

  /// 12 к/с — целевой диапазон 10–15.
  static const fps = 12;

  /// Верхняя граница кадров/с (web getUserMedia).
  static const maxFps = 15;

  /// ~280 kbps — файл ~2 МБ/мин, до ~40 мин в лимите 120 МБ.
  static const videoBitrate = 280000;

  /// Длина одного фрагмента для загрузки на сервер.
  static const segmentDuration = Duration(seconds: 10);
}
