import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/env.dart';
import '../services/token_storage.dart';

String _err(dynamic data, String fallback) {
  final s = formatApiErrorBody(data).trim();
  return s.isEmpty ? fallback : s;
}

/// Не подставлять JWT на шагах входа — старый токен не должен уходить вместе с verify-otp / phone-login.
bool _skipAuthHeaderForPath(String path) {
  return path.contains('verify-otp') ||
      path.contains('phone-login') ||
      path.contains('check-driver-phone');
}

String formatApiErrorBody(dynamic data) {
  if (data == null) return '';
  if (data is String) {
    final t = data.trim();
    if (t.isEmpty) return '';
    final lower = t.toLowerCase();
    if (lower.startsWith('<!doctype') ||
        lower.startsWith('<html') ||
        lower.contains('<title>page not found')) {
      return '';
    }
    if (t.length > 400) return '';
    return t;
  }
  if (data is Map) {
    final e = data['error'] ?? data['detail'];
    if (e is String) return e;
    if (e is List) return e.map((x) => x.toString()).join('; ');
    if (data['non_field_errors'] is List) {
      return (data['non_field_errors'] as List).map((x) => x.toString()).join('; ');
    }
    final parts = <String>[];
    for (final entry in data.entries) {
      final k = entry.key.toString();
      if (k == 'error' || k == 'detail') continue;
      final v = entry.value;
      if (v is List) {
        for (final x in v) {
          final s = x?.toString().trim() ?? '';
          if (s.isNotEmpty) parts.add(s);
        }
      } else if (v is String && v.trim().isNotEmpty) {
        parts.add(v.trim());
      }
    }
    if (parts.isNotEmpty) return parts.join(' ');
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }
  return data.toString();
}

class InvoApi {
  InvoApi(this._tokens) {
    _dio = Dio(
      BaseOptions(
        baseUrl: mobileApiPrefix,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final a = await _tokens.readAccess();
          if (a != null &&
              a.isNotEmpty &&
              !_skipAuthHeaderForPath(options.path)) {
            options.headers['Authorization'] = 'Bearer $a';
          }
          return handler.next(options);
        },
        onError: (err, handler) async {
          final code = err.response?.statusCode;
          final path = err.requestOptions.path;
          if (code == 401 &&
              !path.contains('refresh-token') &&
              !path.contains('verify-otp') &&
              !path.contains('phone-login') &&
              !path.contains('check-driver-phone')) {
            final ok = await _tryRefresh();
            if (ok) {
              final a = await _tokens.readAccess();
              err.requestOptions.headers['Authorization'] = 'Bearer $a';
              try {
                final res = await _dio.fetch(err.requestOptions);
                return handler.resolve(res);
              } catch (e) {
                if (e is DioException) return handler.next(e);
              }
            }
          }
          return handler.next(err);
        },
      ),
    );
  }

  final TokenStorage _tokens;
  late final Dio _dio;

  Future<bool> _tryRefresh() async {
    final refresh = await _tokens.readRefresh();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final plain = Dio(BaseOptions(baseUrl: mobileApiPrefix));
      final r = await plain.post<Map<String, dynamic>>(
        'auth/refresh-token/',
        data: {'refresh': refresh},
      );
      final data = r.data;
      if (data == null || r.statusCode != 200) return false;
      final access = data['access'] as String?;
      if (access == null) return false;
      await _tokens.writeAccess(access);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestOtp(String phone, {bool forDriver = false}) async {
    final p = phone.trim();
    try {
      await _dio.post<Map<String, dynamic>>(
        'auth/phone-login/',
        data: {
          'phone': p,
          if (forDriver) 'for_driver': true,
        },
      );
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Ошибка отправки кода'));
    }
  }

  /// Проверяет, что номер принадлежит водителю; возвращает телефон в формате из БД.
  Future<String> checkDriverPhone(String phone) async {
    final p = phone.trim();
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        'auth/check-driver-phone/',
        data: {'phone': p},
      );
      final canonical = r.data?['phone'] as String?;
      if (canonical == null || canonical.isEmpty) throw Exception('Пустой ответ');
      return canonical;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 404) {
        final parsed = _err(e.response?.data, '');
        if (parsed.isNotEmpty) {
          throw Exception(parsed);
        }
        throw Exception(
          'Проверка номера на сервере недоступна. Обновите backend до версии с check-driver-phone и перезапустите его.',
        );
      }
      throw Exception(_err(e.response?.data, 'Водитель с таким номером не найден'));
    }
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String code, {bool forDriver = false}) async {
    final p = phone.trim();
    final c = code.replaceAll(RegExp(r'\D'), '');
    final Response<Map<String, dynamic>> r;
    try {
      r = await _dio.post<Map<String, dynamic>>(
        'auth/verify-otp/',
        data: {
          'phone': p,
          'code': c,
          if (forDriver) 'for_driver': true,
        },
      );
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Неверный код'));
    }
    final data = r.data;
    if (data == null) throw Exception('Пустой ответ');
    final access = data['access'] as String?;
    final refresh = data['refresh'] as String?;
    if (access == null || refresh == null) throw Exception('Нет токенов в ответе');
    await _tokens.writeTokens(access: access, refresh: refresh);
    return data;
  }

  Future<Map<String, dynamic>> getDriverProfile() async {
    final r = await _dio.get<Map<String, dynamic>>('drivers/profile/');
    if (r.statusCode != 200 || r.data == null) {
      throw Exception(_err(r.data, 'Профиль недоступен'));
    }
    return r.data!;
  }

  Future<Map<String, dynamic>> patchDriverProfile(Map<String, dynamic> data) async {
    try {
      final r = await _dio.patch<Map<String, dynamic>>('drivers/profile/', data: data);
      if (r.statusCode != 200 || r.data == null) {
        throw Exception(_err(r.data, 'Не удалось сохранить профиль'));
      }
      return r.data!;
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Не удалось сохранить профиль'));
    }
  }

  Future<Map<String, dynamic>> patchOnlineStatus(bool isOnline) async {
    final r = await _dio.patch<Map<String, dynamic>>(
      'drivers/online-status/',
      data: {'is_online': isOnline},
    );
    if (r.statusCode != 200 || r.data == null) {
      throw Exception(_err(r.data, 'Не удалось обновить статус'));
    }
    return r.data!;
  }

  Future<void> patchLocation(double lat, double lon) async {
    await _dio.patch('drivers/location/', data: {'lat': lat, 'lon': lon});
  }

  Future<Map<String, dynamic>> getOrders({String? status, int limit = 50}) async {
    final r = await _dio.get<Map<String, dynamic>>(
      'drivers/orders/',
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        'limit': limit,
      },
    );
    if (r.statusCode != 200 || r.data == null) {
      throw Exception(_err(r.data, 'Список заказов'));
    }
    return r.data!;
  }

  /// Очередь активных заказов в порядке исполнения (queue_index, is_current).
  Future<Map<String, dynamic>> getOrderQueue() async {
    final r = await _dio.get<Map<String, dynamic>>('drivers/order-queue/');
    if (r.statusCode != 200 || r.data == null) {
      throw Exception(_err(r.data, 'Очередь заказов'));
    }
    return r.data!;
  }

  /// Маршрутный лист водителя на день.
  Future<Map<String, dynamic>> getDayRoute({String? date}) async {
    final r = await _dio.get<Map<String, dynamic>>(
      'drivers/day-route/',
      queryParameters: {if (date != null && date.isNotEmpty) 'date': date},
    );
    if (r.statusCode != 200 || r.data == null) {
      throw Exception(_err(r.data, 'Маршрут на день'));
    }
    return r.data!;
  }

  Future<Map<String, dynamic>> getOffers() async {
    final r = await _dio.get<Map<String, dynamic>>('drivers/offers/');
    if (r.statusCode != 200 || r.data == null) {
      throw Exception(_err(r.data, 'Предложения'));
    }
    return r.data!;
  }

  Future<void> acceptOffer(int offerId) async {
    try {
      await _dio.post<Map<String, dynamic>>('drivers/offer/$offerId/accept/');
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Не удалось принять'));
    }
  }

  Future<void> declineOffer(int offerId) async {
    try {
      await _dio.post<Map<String, dynamic>>('drivers/offer/$offerId/decline/');
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Не удалось отклонить'));
    }
  }

  Future<Map<String, dynamic>> getOrder(String orderId) async {
    final r = await _dio.get<Map<String, dynamic>>('drivers/order/$orderId/');
    if (r.statusCode != 200 || r.data == null) {
      throw Exception(_err(r.data, 'Заказ'));
    }
    return r.data!;
  }

  /// Активный заказ водителя (может включать route_to_pickup / route для ETA).
  Future<Map<String, dynamic>> getActiveOrder() async {
    final r = await _dio.get<Map<String, dynamic>>('drivers/active-order/');
    if (r.statusCode != 200 || r.data == null) {
      throw Exception(_err(r.data, 'Активный заказ'));
    }
    return r.data!;
  }

  Future<List<Map<String, dynamic>>> getDriverOrderMessages(String orderId, {int limit = 100}) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        'drivers/order/$orderId/messages/',
        queryParameters: {'limit': limit},
      );
      final raw = r.data?['results'];
      if (raw is! List) return [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Сообщения чата'));
    }
  }

  Future<Map<String, dynamic>> postDriverOrderMessage(String orderId, String text) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        'drivers/order/$orderId/messages/',
        data: {'text': text},
      );
      if (r.statusCode != 201 || r.data == null) {
        throw Exception(_err(r.data, 'Отправка сообщения'));
      }
      return Map<String, dynamic>.from(r.data!);
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Отправка сообщения'));
    }
  }

  Future<Map<String, dynamic>> getOrderRoute(String orderId) async {
    final r = await _dio.get<Map<String, dynamic>>('orders/$orderId/route/');
    if (r.statusCode != 200 || r.data == null) {
      throw Exception(_err(r.data, 'Маршрут'));
    }
    return r.data!;
  }

  /// Маршрут до точки забора: при [fromLat]/[fromLon] считается от этих координат (GPS), иначе — с сервера.
  /// Возвращает `null`, если маршрут недоступен.
  Future<Map<String, dynamic>?> getOrderRouteToPickup(
    String orderId, {
    double? fromLat,
    double? fromLon,
  }) async {
    try {
      final q = <String, dynamic>{};
      if (fromLat != null) q['from_lat'] = fromLat;
      if (fromLon != null) q['from_lon'] = fromLon;
      final r = await _dio.get<Map<String, dynamic>>(
        'orders/$orderId/route-to-pickup/',
        queryParameters: q.isEmpty ? null : q,
      );
      if (r.statusCode != 200 || r.data == null) return null;
      return r.data!;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 400 || code == 403 || code == 404) return null;
      throw Exception(_err(e.response?.data, 'Маршрут до забора'));
    }
  }

  /// Маршрут до точки высадки: при [fromLat]/[fromLon] — от GPS, иначе с сервера.
  Future<Map<String, dynamic>?> getOrderRouteToDropoff(
    String orderId, {
    double? fromLat,
    double? fromLon,
  }) async {
    try {
      final q = <String, dynamic>{};
      if (fromLat != null) q['from_lat'] = fromLat;
      if (fromLon != null) q['from_lon'] = fromLon;
      final r = await _dio.get<Map<String, dynamic>>(
        'orders/$orderId/route-to-dropoff/',
        queryParameters: q.isEmpty ? null : q,
      );
      if (r.statusCode != 200 || r.data == null) return null;
      return r.data!;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 400 || code == 403 || code == 404) return null;
      throw Exception(_err(e.response?.data, 'Маршрут до высадки'));
    }
  }

  Future<void> patchOrderStatus(String orderId, String status, {String? reason}) async {
    try {
      final data = <String, dynamic>{'status': status};
      if (reason != null) data['reason'] = reason;
      await _dio.patch<Map<String, dynamic>>(
        'orders/$orderId/status/',
        data: data,
      );
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Статус'));
    }
  }

  Future<Map<String, dynamic>> getStatistics() async {
    final r = await _dio.get<Map<String, dynamic>>('drivers/statistics/');
    if (r.statusCode != 200 || r.data == null) {
      throw Exception(_err(r.data, 'Статистика'));
    }
    return r.data!;
  }

  Future<Map<String, dynamic>> getDriverOrderComplaint(String orderId) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('drivers/order/$orderId/complaint/');
      if (r.statusCode != 200 || r.data == null) {
        throw Exception(_err(r.data, 'Жалоба'));
      }
      return r.data!;
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Жалоба'));
    }
  }

  Future<void> startCabinRecording(String orderId) async {
    try {
      await _dio.post<Map<String, dynamic>>('drivers/order/$orderId/cabin-recording/start/');
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Старт записи салона'));
    }
  }

  Future<void> uploadCabinFrame(String orderId, XFile frame) async {
    try {
      final bytes = await frame.readAsBytes();
      final form = FormData.fromMap({
        'frame': MultipartFile.fromBytes(
          bytes,
          filename: 'frame.jpg',
        ),
      });
      await _dio.post<Map<String, dynamic>>(
        'drivers/order/$orderId/cabin-recording/frame/',
        data: form,
      );
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Загрузка кадра'));
    }
  }

  static String _cabinVideoFilename(XFile video) {
    final name = video.name;
    if (name.isNotEmpty) return name;
    final path = video.path;
    if (path.isNotEmpty) {
      return path.replaceAll('\\', '/').split('/').last;
    }
    return kIsWeb ? 'recording.webm' : 'recording.mp4';
  }

  /// Multipart без загрузки всего файла в RAM на Android/iOS.
  Future<MultipartFile> _cabinVideoMultipart(XFile video) async {
    if (!kIsWeb) {
      final path = video.path;
      if (path.isNotEmpty) {
        return MultipartFile.fromFile(
          path,
          filename: _cabinVideoFilename(video),
        );
      }
    }
    final bytes = await video.readAsBytes();
    return MultipartFile.fromBytes(
      bytes,
      filename: _cabinVideoFilename(video),
    );
  }

  Future<void> uploadCabinSegment(String orderId, int segmentIndex, XFile video) async {
    try {
      final form = FormData.fromMap({
        'segment_index': segmentIndex,
        'video': await _cabinVideoMultipart(video),
      });
      await _dio.post<Map<String, dynamic>>(
        'drivers/order/$orderId/cabin-recording/segment/',
        data: form,
        options: Options(
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Загрузка сегмента'));
    }
  }

  Future<void> uploadCabinVideo(String orderId, XFile video) async {
    try {
      final form = FormData.fromMap({
        'video': await _cabinVideoMultipart(video),
      });
      await _dio.post<Map<String, dynamic>>(
        'drivers/order/$orderId/cabin-recording/video/',
        data: form,
        options: Options(
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Загрузка видео'));
    }
  }

  Future<void> finishCabinRecording(
    String orderId, {
    XFile? video,
    int? segmentIndex,
  }) async {
    try {
      final map = <String, dynamic>{};
      if (video != null) {
        map['video'] = await _cabinVideoMultipart(video);
        if (segmentIndex != null) {
          map['segment_index'] = segmentIndex;
        }
      }
      await _dio.post<Map<String, dynamic>>(
        'drivers/order/$orderId/cabin-recording/finish/',
        data: map.isEmpty ? null : FormData.fromMap(map),
        options: Options(
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Завершение записи'));
    }
  }

  Future<Map<String, dynamic>> submitDriverOrderComplaint(
    String orderId, {
    required String category,
    required String description,
    String? attachmentPath,
  }) async {
    try {
      final map = <String, dynamic>{
        'category': category,
        'description': description,
      };
      if (attachmentPath != null && attachmentPath.isNotEmpty) {
        map['attachment'] = await MultipartFile.fromFile(
          attachmentPath,
          filename: attachmentPath.replaceAll('\\', '/').split('/').last,
        );
      }
      final form = FormData.fromMap(map);
      final r = await _dio.post<Map<String, dynamic>>(
        'drivers/order/$orderId/complaint/',
        data: form,
      );
      if (r.statusCode != 201 || r.data == null) {
        throw Exception(_err(r.data, 'Не удалось отправить жалобу'));
      }
      return r.data!;
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'Не удалось отправить жалобу'));
    }
  }

  /// Общий FAQ (тот же список, что у пассажира; доступен любому авторизованному пользователю).
  Future<List<Map<String, dynamic>>> getFaq() async {
    try {
      final r = await _dio.get<dynamic>('passengers/faq/');
      if (r.statusCode != 200 || r.data == null) {
        throw Exception(_err(r.data, 'FAQ'));
      }
      final data = r.data;
      if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } on DioException catch (e) {
      throw Exception(_err(e.response?.data, 'FAQ'));
    }
  }

  Future<void> logout() async {
    final refresh = await _tokens.readRefresh();
    try {
      final body = <String, dynamic>{};
      if (refresh != null) body['refresh'] = refresh;
      await _dio.post('auth/logout/', data: body);
    } catch (_) {}
    await _tokens.clear();
  }
}
