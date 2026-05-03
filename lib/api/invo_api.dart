import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/env.dart';
import '../services/token_storage.dart';

String _err(dynamic data, String fallback) {
  final s = formatApiErrorBody(data).trim();
  return s.isEmpty ? fallback : s;
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
          if (a != null && a.isNotEmpty) {
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

  Future<void> requestOtp(String phone) async {
    final p = phone.trim();
    try {
      await _dio.post<Map<String, dynamic>>('auth/phone-login/', data: {'phone': p});
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

  Future<Map<String, dynamic>> verifyOtp(String phone, String code) async {
    final p = phone.trim();
    final c = code.replaceAll(RegExp(r'\D'), '');
    final Response<Map<String, dynamic>> r;
    try {
      r = await _dio.post<Map<String, dynamic>>(
        'auth/verify-otp/',
        data: {'phone': p, 'code': c},
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
