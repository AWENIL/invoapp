import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_providers.dart';
import '../services/cabin_recording_service.dart';
import '../services/driver_camera_permission.dart';
import '../services/driver_location_sync.dart';
import '../widgets/driver_order_complaint_sheet.dart';
import '../widgets/order_route_map.dart';
import 'driver_navigation_screen.dart';
import 'driver_order_chat_screen.dart';

final _orderDetailFamily = FutureProvider.family<Map<String, dynamic>, String>((ref, orderId) async {
  return ref.watch(invoApiProvider).getOrder(orderId);
});

const _primaryOrange = Color(0xFFFF6B44);
const _chipBg = Color(0xFFFFE5E0);

ThemeData _tripLightTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _primaryOrange,
      brightness: Brightness.light,
      primary: _primaryOrange,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.black),
    ),
  );
}

bool _orderAllowsChat(String status) {
  return const {'assigned', 'driver_en_route', 'arrived_waiting', 'ride_ongoing'}.contains(status);
}

String? _passengerNameFromOrder(Map<String, dynamic> order) {
  final p = order['passenger'];
  if (p is Map) {
    final n = p['full_name']?.toString().trim();
    if (n != null && n.isNotEmpty) return n;
  }
  final n2 = order['passenger_name']?.toString().trim();
  if (n2 != null && n2.isNotEmpty) return n2;
  return null;
}

String? _passengerPhoneFromOrder(Map<String, dynamic> order) {
  final top = order['passenger_phone']?.toString().trim();
  if (top != null && top.isNotEmpty) return top;
  final p = order['passenger'];
  if (p is Map) {
    final ph = p['phone']?.toString().trim();
    if (ph != null && ph.isNotEmpty) return ph;
    final uh = (p['user'] is Map ? (p['user'] as Map)['phone'] : null)?.toString().trim();
    if (uh != null && uh.isNotEmpty) return uh;
  }
  return null;
}

String _orderDisplayNo(String id) {
  final parts = id.split('-');
  if (parts.length >= 5) {
    final a = parts[1].length >= 2 ? parts[1].substring(0, 2) : parts[1];
    final b = parts[4].length >= 2 ? parts[4].substring(parts[4].length - 2) : parts[4];
    return '№${a.toUpperCase()}-${b.toUpperCase()}';
  }
  if (id.length <= 12) return '№$id';
  return '№${id.substring(0, 6)}…${id.substring(id.length - 2)}';
}

String _shortPassengerLabel(String? full) {
  if (full == null || full.isEmpty) return '—';
  final parts = full.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) return parts[0];
  final second = parts[1];
  if (second.isEmpty) return parts[0];
  return '${parts[0]} ${second[0].toUpperCase()}.';
}

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.embeddedInShell = false,
  });

  final String orderId;

  /// С вкладки «Поездка»: без стрелки в AppBar; на экране завершения «Назад» ведёт на вкладку «Заказ».
  final bool embeddedInShell;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  Timer? _pollTimer;
  Timer? _navRefreshTimer;
  Timer? _waitTicker;
  int? _waitDisplaySeconds;
  double? _navFromLat;
  double? _navFromLon;
  Map<String, dynamic>? _activeMeta;
  bool _busy = false;
  String? _lastFetchedMetaStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNavOrigin());
  }

  @override
  void dispose() {
    _stopPoll();
    _stopNavRefresh();
    _stopWaitTicker();
    super.dispose();
  }

  void _onCompletedDismiss(BuildContext context) {
    ref.invalidate(driverOrdersProvider);
    ref.invalidate(driverHistoryOrdersProvider);
    if (widget.embeddedInShell) {
      ref.read(driverShellTabIndexProvider.notifier).state = 0;
    } else if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _ensureWaitTicker() {
    _waitTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_waitDisplaySeconds == null || _waitDisplaySeconds! <= 0) return;
      setState(() => _waitDisplaySeconds = _waitDisplaySeconds! - 1);
    });
  }

  void _stopWaitTicker() {
    _waitTicker?.cancel();
    _waitTicker = null;
  }

  void _syncWaitSecondsFromOrder(Map<String, dynamic> order) {
    if ((order['status']?.toString() ?? '') != 'arrived_waiting') {
      if (_waitDisplaySeconds != null) {
        setState(() => _waitDisplaySeconds = null);
      }
      return;
    }
    final sec = order['waiting_free_remaining_seconds'];
    if (sec is! num) return;
    final serverVal = sec.round().clamp(0, 86400);
    if (_waitDisplaySeconds == null) {
      setState(() => _waitDisplaySeconds = serverVal);
      return;
    }
    if ((serverVal - _waitDisplaySeconds!).abs() > 2) {
      setState(() => _waitDisplaySeconds = serverVal);
    }
  }

  Future<void> _loadNavOrigin() async {
    final pos = await DriverLocationSync.getCurrentPositionOrNull();
    double? lat = pos?.latitude;
    double? lon = pos?.longitude;
    if (lat == null && mounted) {
      final session = ref.read(sessionProvider).valueOrNull;
      if (session != null) {
        lat = (session.profile['current_lat'] as num?)?.toDouble();
        lon = (session.profile['current_lon'] as num?)?.toDouble();
      }
    }
    if (!mounted) return;
    setState(() {
      _navFromLat = lat;
      _navFromLon = lon;
    });
  }

  void _ensurePoll() {
    _pollTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      ref.invalidate(_orderDetailFamily(widget.orderId));
    });
  }

  void _stopPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Периодическое обновление координат для карты (еду к подаче / в поездке).
  void _ensureNavRefresh() {
    _navRefreshTimer ??= Timer.periodic(const Duration(seconds: 12), (_) {
      _refreshNavForMapAndBackend();
    });
  }

  void _stopNavRefresh() {
    _navRefreshTimer?.cancel();
    _navRefreshTimer = null;
  }

  Future<void> _refreshNavForMapAndBackend() async {
    await _loadNavOrigin();
    if (!mounted) return;
    final lat = _navFromLat;
    final lon = _navFromLon;
    if (lat == null || lon == null) return;
    try {
      await ref.read(invoApiProvider).patchLocation(lat, lon);
    } catch (_) {}
  }

  Future<void> _refreshActiveMeta(String status, String orderId) async {
    if (!const {'assigned', 'driver_en_route', 'ride_ongoing'}.contains(status)) {
      if (mounted) setState(() => _activeMeta = null);
      return;
    }
    try {
      final a = await ref.read(invoApiProvider).getActiveOrder();
      if (!mounted) return;
      if (a['has_active_order'] != true) {
        setState(() => _activeMeta = null);
        return;
      }
      final oid = a['id']?.toString();
      if (oid != orderId) {
        setState(() => _activeMeta = null);
        return;
      }
      setState(() => _activeMeta = Map<String, dynamic>.from(a));
    } catch (_) {}
  }

  Future<void> _patchArrived() async {
    setState(() => _busy = true);
    try {
      await ref.read(invoApiProvider).patchOrderStatus(
            widget.orderId,
            'arrived_waiting',
            reason: 'Прибыл',
          );
      ref.invalidate(_orderDetailFamily(widget.orderId));
      ref.invalidate(driverOrdersProvider);
      ref.invalidate(driverActiveOrderProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startOrderToPickup() async {
    setState(() => _busy = true);
    try {
      // Сначала фиксируем позицию водителя: для карты (TripSegmentMap) и для ETA на сервере
      // (get_active_order → route_to_pickup считает от driver.current_lat/lon).
      await _loadNavOrigin();
      final lat = _navFromLat;
      final lon = _navFromLon;
      if (lat != null && lon != null) {
        try {
          await ref.read(invoApiProvider).patchLocation(lat, lon);
        } catch (_) {}
      }
      await ref.read(invoApiProvider).patchOrderStatus(
            widget.orderId,
            'driver_en_route',
            reason: 'Выехал к точке забора',
          );
      ref.invalidate(_orderDetailFamily(widget.orderId));
      ref.invalidate(driverOrdersProvider);
      ref.invalidate(driverActiveOrderProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _patchStatus(String next, String reason) async {
    setState(() => _busy = true);
    try {
      final currentStatus =
          ref.read(_orderDetailFamily(widget.orderId)).valueOrNull?['status']?.toString() ?? '';
      if (currentStatus == 'ride_ongoing' && next != 'ride_ongoing') {
        await ref.read(cabinRecordingServiceProvider).stopAndUploadIfActive(widget.orderId);
      }

      // Камера обязательна — без неё не переводим заказ в ride_ongoing.
      if (next == 'ride_ongoing' && CabinRecordingService.platformSupportsRecording) {
        final granted = await DriverCameraPermission.ensureGranted();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Невозможно начать поездку без камеры. '
                  'Разрешите камеру в настройках сайта (значок камеры в адресной строке).',
                ),
                duration: Duration(seconds: 6),
              ),
            );
          }
          return;
        }
      }

      await ref.read(invoApiProvider).patchOrderStatus(widget.orderId, next, reason: reason);
      ref.invalidate(_orderDetailFamily(widget.orderId));
      ref.invalidate(driverOrdersProvider);
      ref.invalidate(driverActiveOrderProvider);

      if (next == 'ride_ongoing') {
        final service = ref.read(cabinRecordingServiceProvider);
        final ok = await service.syncWithOrder({
          'id': widget.orderId,
          'status': 'ride_ongoing',
        });
        if (mounted && !ok) {
          final err = service.lastError ?? 'камера или сервер недоступны';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось начать запись салона: $err')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _conflict() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Обратитесь к диспетчеру для разрешения конфликта.')),
    );
  }

  Future<void> _openPhone(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openYandexRoute(
    double fromLat,
    double fromLon,
    double toLat,
    double toLon,
  ) async {
    final u = Uri.parse(yandexRouteUrl(fromLat, fromLon, toLat, toLon));
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть Яндекс.Карты')),
      );
    }
  }

  String _formatWaitMmSs(Map<String, dynamic> order, {int? displayRemaining}) {
    final sec = displayRemaining ??
        ((order['waiting_free_remaining_seconds'] is num)
            ? (order['waiting_free_remaining_seconds'] as num).round()
            : null);
    if (sec == null) return '00:00';
    final s = sec.clamp(0, 86400);
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  double _waitProgress(Map<String, dynamic> order, {int? displayRemaining}) {
    final remaining = displayRemaining ??
        ((order['waiting_free_remaining_seconds'] is num)
            ? (order['waiting_free_remaining_seconds'] as num).round()
            : null);
    final minutes = order['waiting_free_minutes'];
    if (remaining == null) return 0;
    final totalSec = (minutes is num && minutes > 0) ? (minutes * 60).round() : 1200;
    if (totalSec <= 0) return 0;
    return (1 - remaining / totalSec).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(_orderDetailFamily(widget.orderId));

    return orderAsync.when(
      loading: () => Theme(
        data: _tripLightTheme(),
        child: Scaffold(
          appBar: AppBar(
            title: Text('Заказ ${widget.orderId}'),
            automaticallyImplyLeading: !widget.embeddedInShell,
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Theme(
        data: _tripLightTheme(),
        child: Scaffold(
          appBar: AppBar(
            title: Text('Заказ ${widget.orderId}'),
            automaticallyImplyLeading: !widget.embeddedInShell,
          ),
          body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
        ),
      ),
      data: (order) {
        final status = order['status']?.toString() ?? '';
        if (status == 'arrived_waiting') {
          _ensurePoll();
          _ensureWaitTicker();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _syncWaitSecondsFromOrder(order);
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadNavOrigin());
        } else {
          _stopPoll();
          _stopWaitTicker();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _syncWaitSecondsFromOrder(order);
          });
        }
        if (status == 'arrived_waiting') {
          _ensureNavRefresh();
        } else if (status == 'driver_en_route' || status == 'ride_ongoing') {
          _stopNavRefresh();
        } else {
          _stopNavRefresh();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_lastFetchedMetaStatus == status) return;
          _lastFetchedMetaStatus = status;
          _refreshActiveMeta(status, widget.orderId);
        });

        return Theme(
          data: _tripLightTheme(),
          child: _busy
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(child: _buildTripScaffold(context, order, status)),
                    const ModalBarrier(dismissible: false, color: Color(0x33000000)),
                    const Center(child: CircularProgressIndicator()),
                  ],
                )
              : _buildTripScaffold(context, order, status),
        );
      },
    );
  }

  Widget _buildTripScaffold(BuildContext context, Map<String, dynamic> order, String status) {
    final pickup = order['pickup_title']?.toString() ?? '';
    final dropObj = order['dropoff_object_name']?.toString().trim();
    final dropTitle = order['dropoff_title']?.toString() ?? '';
    final dropLine = (dropObj != null && dropObj.isNotEmpty) ? dropObj : dropTitle;
    final plat = (order['pickup_lat'] as num?)?.toDouble();
    final plon = (order['pickup_lon'] as num?)?.toDouble();
    final dlat = (order['dropoff_lat'] as num?)?.toDouble();
    final dlon = (order['dropoff_lon'] as num?)?.toDouble();
    final mapH = MediaQuery.sizeOf(context).height * 0.40;

    if (status == 'driver_en_route' || status == 'ride_ongoing') {
      return DriverNavigationScreen(
        orderId: widget.orderId,
        order: order,
        embeddedInShell: widget.embeddedInShell,
        leg: status == 'driver_en_route' ? DriverNavLeg.toPickup : DriverNavLeg.toDropoff,
        onStatusChanged: () {
          ref.invalidate(_orderDetailFamily(widget.orderId));
          ref.invalidate(driverOrdersProvider);
          ref.invalidate(driverActiveOrderProvider);
        },
      );
    }

    if (status == 'completed') {
      final w = order['waiting_time_minutes'];
      final d = order['distance_km'];
      final waitStr = w is num ? '${w.round()} мин' : '—';
      final distStr = d is num ? '${NumberFormat('#0.0', 'ru_RU').format(d)} км' : '—';
      final pName = _shortPassengerLabel(_passengerNameFromOrder(order));
      final hasCompanion = order['has_companion'] == true;
      final orderNo = _orderDisplayNo(widget.orderId);

      return Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => _onCompletedDismiss(context),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: mapH,
                    width: double.infinity,
                    child: _buildCompletedRouteMap(
                      plat: plat,
                      plon: plon,
                      dlat: dlat,
                      dlon: dlon,
                      mapH: mapH,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -4)),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Детали поездки',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.grey.shade900),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '$orderNo · $waitStr',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _chipBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Завершено',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFC62828)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _completedLocationRow(icon: Icons.near_me, label: pickup),
                      const SizedBox(height: 12),
                      _completedLocationRow(icon: Icons.flag_outlined, label: dropLine.isNotEmpty ? dropLine : '—'),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _completedStatTile('Время', waitStr),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _completedStatTile('Расстояние', distStr),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.grey.shade200,
                              child: Icon(Icons.person_outline, color: Colors.grey.shade700),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pName,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Пассажир',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            if (hasCompanion)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _chipBg,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Сопровождающий',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _primaryOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => openDriverOrderComplaint(context, widget.orderId),
                          child: const Text('Подать жалобу', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => _onCompletedDismiss(context),
                          child: const Text('Готов к новому заказу', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final waitMin = order['waiting_free_minutes'];
    final appTitle = status == 'arrived_waiting' && waitMin is num
        ? 'Ожидание ${waitMin.round()} минут'
        : 'Поездка';

    return Scaffold(
      appBar: AppBar(
        title: Text(appTitle),
        automaticallyImplyLeading: !widget.embeddedInShell,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: mapH,
            width: double.infinity,
            child: _buildMapArea(
              status: status,
              plat: plat,
              plon: plon,
              dlat: dlat,
              dlon: dlon,
              mapH: mapH,
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -4)),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: _buildSheet(
                  context,
                  order,
                  status,
                  pickup,
                  dropLine,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedRouteMap({
    required double? plat,
    required double? plon,
    required double? dlat,
    required double? dlon,
    required double mapH,
  }) {
    if (plat == null || plon == null || dlat == null || dlon == null) {
      return Container(
        color: const Color(0xFFE8E8E8),
        alignment: Alignment.center,
        child: const Icon(Icons.map_outlined, size: 48, color: Colors.grey),
      );
    }
    return TripSegmentMap(
      fromLat: plat,
      fromLon: plon,
      toLat: dlat,
      toLon: dlon,
      mapHeight: mapH,
      showOpenInExternalMapsButton: false,
    );
  }

  Widget _completedLocationRow({required IconData icon, required String label}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: Colors.black87),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget _completedStatTile(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildMapArea({
    required String status,
    required double? plat,
    required double? plon,
    required double? dlat,
    required double? dlon,
    required double mapH,
  }) {
    if (plat == null || plon == null) {
      return Container(
        color: const Color(0xFFE8E8E8),
        alignment: Alignment.center,
        child: const Icon(Icons.map_outlined, size: 48, color: Colors.grey),
      );
    }

    if (status == 'arrived_waiting') {
      var fLat = _navFromLat ?? plat;
      var fLon = _navFromLon ?? plon;
      if ((fLat - plat).abs() < 1e-5 && (fLon - plon).abs() < 1e-5) {
        fLat = plat + 0.002;
        fLon = plon + 0.002;
      }
      return TripSegmentMap(
        fromLat: fLat,
        fromLon: fLon,
        toLat: plat,
        toLon: plon,
        mapHeight: mapH,
        showOpenInExternalMapsButton: false,
      );
    }

    if (status == 'assigned') {
      return Container(
        color: const Color(0xFFE8E8E8),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_circle_outline, size: 56, color: Colors.orange.shade700),
              const SizedBox(height: 12),
              Text(
                'Нажмите «Начать заказ» ниже — откроется маршрут к точке подачи',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.35),
              ),
            ],
          ),
        ),
      );
    }

    final fromLat = _navFromLat ?? plat;
    final fromLon = _navFromLon ?? plon;

    if (status == 'driver_en_route') {
      if (_navFromLat == null || _navFromLon == null) {
        return Container(
          color: const Color(0xFFE8E8E8),
          alignment: Alignment.center,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _primaryOrange),
              SizedBox(height: 12),
              Text('Определяем вашу позицию…'),
            ],
          ),
        );
      }
      return TripSegmentMap(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: plat,
        toLon: plon,
        mapHeight: mapH,
        showOpenInExternalMapsButton: false,
      );
    }

    if (status == 'ride_ongoing' && dlat != null && dlon != null) {
      return TripSegmentMap(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: dlat,
        toLon: dlon,
        mapHeight: mapH,
        showOpenInExternalMapsButton: false,
      );
    }

    return Container(
      color: const Color(0xFFE8E8E8),
      alignment: Alignment.center,
      child: const Icon(Icons.map_outlined, size: 48, color: Colors.grey),
    );
  }

  Widget _buildSheet(
    BuildContext context,
    Map<String, dynamic> order,
    String status,
    String pickup,
    String dropLine,
  ) {
    final pName = _passengerNameFromOrder(order);
    final phone = _passengerPhoneFromOrder(order);
    final routeToPickup = _activeMeta?['route_to_pickup'] as Map?;
    final routeRide = _activeMeta?['route'] as Map?;
    final plat = (order['pickup_lat'] as num?)?.toDouble();
    final plon = (order['pickup_lon'] as num?)?.toDouble();
    final dlat = (order['dropoff_lat'] as num?)?.toDouble();
    final dlon = (order['dropoff_lon'] as num?)?.toDouble();
    final navFromLat = _navFromLat ?? plat;
    final navFromLon = _navFromLon ?? plon;

    Widget routeSubtitle() {
      if (status == 'driver_en_route') {
        final km = routeToPickup?['distance_km'];
        final min = routeToPickup?['duration_minutes'];
        if (km is num && min is num) {
          return Text(
            '${km.toStringAsFixed(1)} км · ${min.round()} мин',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
          );
        }
      }
      if (status == 'ride_ongoing') {
        final km = routeRide?['distance_km'];
        final min = routeRide?['duration_minutes'];
        if (km is num && min is num) {
          return Text(
            '${km.toStringAsFixed(1)} км · ${min.round()} мин',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
          );
        }
      }
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Пассажир', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text(
                    pName ?? '—',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            if (_orderAllowsChat(status)) ...[
              _roundIconButton(
                icon: Icons.chat_bubble_outline,
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => DriverOrderChatScreen(
                        orderId: widget.orderId,
                        passengerName: pName,
                        passengerPhone: phone,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              _roundIconButton(
                icon: Icons.phone_outlined,
                onPressed: () => _openPhone(phone),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        routeSubtitle(),
        const SizedBox(height: 16),
        if (status == 'ride_ongoing') ...[
          Builder(
            builder: (context) {
              final recording = ref.watch(cabinRecordingServiceProvider);
              final active = recording.isRecording;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: active ? Colors.red.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: active ? Colors.red.shade200 : Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      active ? Icons.fiber_manual_record : Icons.videocam_outlined,
                      color: active ? Colors.red.shade700 : Colors.orange.shade800,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        active
                            ? 'Идёт видеозапись салона. Фрагменты по 10 сек отправляются диспетчеру.'
                            : 'Запуск записи салона… Если не началась — проверьте доступ к камере.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: active ? Colors.red.shade900 : Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text('Поездка', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          _locationTile(icon: Icons.check_circle_outline, title: pickup, subtitle: 'Посадка'),
          const SizedBox(height: 10),
          _locationTile(icon: Icons.check_circle_outline, title: dropLine, subtitle: 'Высадка'),
          const SizedBox(height: 12),
          if (plat != null &&
              plon != null &&
              dlat != null &&
              dlon != null &&
              navFromLat != null &&
              navFromLon != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed:
                    _busy ? null : () => _openYandexRoute(navFromLat, navFromLon, dlat, dlon),
                icon: Icon(Icons.map_outlined, size: 20, color: Colors.orange.shade800),
                label: Text(
                  'Открыть маршрут в Яндекс.Картах',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Expanded(child: _miniAction('Чат', Icons.chat_bubble_outline, () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => DriverOrderChatScreen(
                      orderId: widget.orderId,
                      passengerName: pName,
                      passengerPhone: phone,
                    ),
                  ),
                );
              })),
              const SizedBox(width: 8),
              Expanded(child: _miniAction('Конфликт', Icons.shield_outlined, _conflict)),
              const SizedBox(width: 8),
              Expanded(child: _miniAction('Поделиться', Icons.share_outlined, () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Скоро')),
                );
              })),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : () => _patchStatus('completed', 'Завершено'),
              child: const Text('Завершить поездку', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
          ),
        ] else if (status == 'arrived_waiting') ...[
          Text(
            'Бесплатное ожидание',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            _formatWaitMmSs(order, displayRemaining: _waitDisplaySeconds),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
          Text(
            'Ждите пассажира до окончания таймера',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _waitProgress(order, displayRemaining: _waitDisplaySeconds),
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              color: _primaryOrange,
            ),
          ),
          const SizedBox(height: 20),
          _locationTile(
            icon: Icons.navigation_outlined,
            title: pickup,
            subtitle: 'Точка посадки',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _roundIconButton(
                  icon: Icons.chat_bubble_outline,
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => DriverOrderChatScreen(
                          orderId: widget.orderId,
                          passengerName: pName,
                          passengerPhone: phone,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                _roundIconButton(icon: Icons.phone_outlined, onPressed: () => _openPhone(phone)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _chipBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.videocam_outlined, color: Colors.orange.shade800, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'После «Начать поездку» автоматически включится запись салона до завершения поездки.',
                    style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : () => _patchStatus('ride_ongoing', 'Поездка началась'),
              child: const Text('Начать поездку', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
          ),
        ] else if (status == 'assigned') ...[
          Text('К точке подачи', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          _locationTile(
            icon: Icons.place_outlined,
            title: pickup,
            subtitle: 'Адрес посадки',
          ),
          const SizedBox(height: 16),
          Text(
            'Начните заказ, когда будете готовы выехать. Затем откроется маршрут в навигаторе.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : _startOrderToPickup,
              child: const Text('Начать заказ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryOrange,
                side: const BorderSide(color: _primaryOrange),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _conflict,
              child: const Text('Конфликт', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
          ),
        ] else if (status == 'driver_en_route') ...[
          _locationTile(icon: Icons.navigation_outlined, title: pickup, subtitle: 'Точка посадки'),
          if (plat != null &&
              plon != null &&
              navFromLat != null &&
              navFromLon != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed:
                    _busy ? null : () => _openYandexRoute(navFromLat, navFromLon, plat, plon),
                icon: Icon(Icons.map_outlined, size: 20, color: Colors.orange.shade800),
                label: Text(
                  'Открыть маршрут в Яндекс.Картах',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : _patchArrived,
              child: const Text('Я приехал', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryOrange,
                side: const BorderSide(color: _primaryOrange),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _conflict,
              child: const Text('Конфликт', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
          ),
        ] else ...[
          Text(
            'Статус: $status',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }

  Widget _locationTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Colors.black87),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _roundIconButton({required IconData icon, required VoidCallback onPressed}) {
    return Material(
      color: _chipBg,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: _primaryOrange, size: 22),
        ),
      ),
    );
  }

  Widget _miniAction(String label, IconData icon, VoidCallback onTap) {
    return Material(
      color: _chipBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(icon, color: _primaryOrange, size: 20),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _primaryOrange)),
            ],
          ),
        ),
      ),
    );
  }
}
