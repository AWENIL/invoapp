import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invo_common/invo_common.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_providers.dart';
import '../services/cabin_recording_service.dart';
import '../services/driver_camera_permission.dart';
import '../services/driver_location_sync.dart';
import '../services/driver_navigation_location.dart';
import '../services/driver_route_progress.dart';
import '../widgets/driver_navigation_map.dart';
import 'driver_order_chat_screen.dart';

const _primaryOrange = Color(0xFFFF6B44);

enum DriverNavLeg { toPickup, toDropoff }

class DriverNavigationScreen extends ConsumerStatefulWidget {
  const DriverNavigationScreen({
    super.key,
    required this.orderId,
    required this.order,
    required this.leg,
    this.embeddedInShell = false,
    this.onStatusChanged,
  });

  final String orderId;
  final Map<String, dynamic> order;
  final DriverNavLeg leg;
  final bool embeddedInShell;
  final VoidCallback? onStatusChanged;

  @override
  ConsumerState<DriverNavigationScreen> createState() => _DriverNavigationScreenState();
}

class _DriverNavigationScreenState extends ConsumerState<DriverNavigationScreen> {
  final _locationService = DriverNavigationLocationService();
  final _sheetController = DraggableScrollableController();

  Map<String, dynamic>? _routePayload;
  DriverRouteProgressTracker? _tracker;
  DriverNavSnapshot? _snapshot;
  double? _driverLat;
  double? _driverLon;
  double _driverHeading = 0;
  bool _loadingRoute = true;
  bool _locationDenied = false;
  bool _busy = false;
  DateTime? _lastRerouteAt;
  String? _routeRequestKey;

  double? get _toLat {
    if (widget.leg == DriverNavLeg.toPickup) {
      return (widget.order['pickup_lat'] as num?)?.toDouble();
    }
    return (widget.order['dropoff_lat'] as num?)?.toDouble();
  }

  double? get _toLon {
    if (widget.leg == DriverNavLeg.toPickup) {
      return (widget.order['pickup_lon'] as num?)?.toDouble();
    }
    return (widget.order['dropoff_lon'] as num?)?.toDouble();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  @override
  void didUpdateWidget(DriverNavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leg != widget.leg) {
      _fetchRoute(force: true);
    }
  }

  @override
  void dispose() {
    _locationService.stop();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final permissionFuture = _locationService.ensurePermission();
    final posFuture = DriverLocationSync.getCurrentPositionOrNull();

    // Не ждём GPS — маршрут сразу с сервера (координаты водителя из БД или точка посадки).
    unawaited(_fetchRoute(force: true));

    final ok = await permissionFuture;
    if (!mounted) return;
    if (!ok) {
      setState(() => _locationDenied = true);
    }

    final pos = await posFuture;
    if (mounted && pos != null) {
      setState(() {
        _driverLat = pos.latitude;
        _driverLon = pos.longitude;
      });
      await _fetchRoute(force: true);
    }

    _locationService.start(
      onUpdate: (pos) {
        if (!mounted) return;
        setState(() {
          _driverLat = pos.lat;
          _driverLon = pos.lon;
          _driverHeading = pos.heading;
          final tracker = _tracker;
          if (tracker != null) {
            _snapshot = tracker.update(pos.lat, pos.lon);
            if (_snapshot?.offRoute == true) {
              unawaited(_maybeReroute(pos.lat, pos.lon));
            }
          }
        });
      },
      onBackendPatch: (lat, lon) => ref.read(invoApiProvider).patchLocation(lat, lon),
    );
  }

  Future<void> _fetchRoute({required bool force}) async {
    final toLat = _toLat;
    final toLon = _toLon;
    if (toLat == null || toLon == null) {
      if (mounted) setState(() => _loadingRoute = false);
      return;
    }

    final fromLat = _driverLat;
    final fromLon = _driverLon;
    final key = '${widget.leg.name}:${fromLat?.toStringAsFixed(4)}:${fromLon?.toStringAsFixed(4)}';
    if (!force && key == _routeRequestKey && _routePayload != null) return;
    _routeRequestKey = key;

    setState(() => _loadingRoute = true);
    try {
      final api = ref.read(invoApiProvider);
      final data = widget.leg == DriverNavLeg.toPickup
          ? await api.getOrderRouteToPickup(
              widget.orderId,
              fromLat: fromLat,
              fromLon: fromLon,
            )
          : await api.getOrderRouteToDropoff(
              widget.orderId,
              fromLat: fromLat,
              fromLon: fromLon,
            );
      if (!mounted) return;
      if (data == null) {
        setState(() => _loadingRoute = false);
        return;
      }
      final polyline = parseRoadRoutePoints(data) ?? [];
      final steps = parseDriverRouteSteps(data);
      final tracker = DriverRouteProgressTracker(
        polyline: polyline,
        steps: steps,
        totalDurationSeconds: parseRouteDurationSeconds(data),
        totalDistanceM: parseRouteDistanceM(data),
      );
      final lat = _driverLat ?? fromLat ?? polyline.firstOrNull?.first;
      final lon = _driverLon ?? fromLon ?? polyline.firstOrNull?.last;
      setState(() {
        _routePayload = data;
        _tracker = tracker;
        _loadingRoute = false;
        if (lat != null && lon != null) {
          _snapshot = tracker.update(lat, lon);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  Future<void> _maybeReroute(double lat, double lon) async {
    final last = _lastRerouteAt;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 15)) {
      return;
    }
    _lastRerouteAt = DateTime.now();
    await _fetchRoute(force: true);
  }

  String? _passengerName() {
    final p = widget.order['passenger'];
    if (p is Map) {
      final n = p['full_name']?.toString().trim();
      if (n != null && n.isNotEmpty) return n;
    }
    return widget.order['passenger_name']?.toString();
  }

  String? _passengerPhone() {
    final top = widget.order['passenger_phone']?.toString().trim();
    if (top != null && top.isNotEmpty) return top;
    final p = widget.order['passenger'];
    if (p is Map) {
      final ph = p['phone']?.toString().trim();
      if (ph != null && ph.isNotEmpty) return ph;
    }
    return null;
  }

  Future<void> _patchStatus(String next, String reason) async {
    setState(() => _busy = true);
    try {
      final currentStatus = widget.order['status']?.toString() ?? '';
      if (currentStatus == 'ride_ongoing' && next != 'ride_ongoing') {
        await ref.read(cabinRecordingServiceProvider).stopAndUploadIfActive(widget.orderId);
      }
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
      invalidateDriverOrderQueue(ref);
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
      widget.onStatusChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _patchArrived() async {
    setState(() => _busy = true);
    try {
      await ref.read(invoApiProvider).patchOrderStatus(
            widget.orderId,
            'arrived_waiting',
            reason: 'Прибыл',
          );
      invalidateDriverOrderQueue(ref);
      ref.invalidate(driverActiveOrderProvider);
      widget.onStatusChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPhone(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Widget _buildTopBanner() {
    final snap = _snapshot;
    final step = snap?.nextStep;
    final icon = step == null ? Icons.navigation_outlined : maneuverIcon(step.maneuver);
    return PointerInterceptor(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.white,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              elevation: 2,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: Colors.white,
                elevation: 3,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(icon, color: _primaryOrange, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          snap?.maneuverBanner ?? 'Загрузка маршрута…',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.25),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildBottomPanel() {
    final snap = _snapshot;
    final remainingM = snap?.remainingDistanceM ?? parseRouteDistanceM(_routePayload ?? {});
    final remainingSec = snap?.remainingDurationSeconds ?? parseRouteDurationSeconds(_routePayload ?? {});
    final eta = DateTime.now().add(Duration(seconds: remainingSec));
    final pickup = widget.order['pickup_title']?.toString() ?? '';
    final drop = widget.order['dropoff_object_name']?.toString().trim().isNotEmpty == true
        ? widget.order['dropoff_object_name']!.toString()
        : widget.order['dropoff_title']?.toString() ?? '';

    final primaryLabel = widget.leg == DriverNavLeg.toPickup ? 'Я приехал' : 'Завершить поездку';
    final primaryAction = widget.leg == DriverNavLeg.toPickup ? _patchArrived : () => _patchStatus('completed', 'Завершено');

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.22,
      minChildSize: 0.22,
      maxChildSize: 0.55,
      snap: true,
      snapSizes: const [0.22, 0.55],
      builder: (context, scrollController) {
        return PointerInterceptor(
          child: Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            elevation: 12,
            child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
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
              Text(
                '${formatRemainingDistance(remainingM)} · ~${(remainingSec / 60).ceil()} мин · ${formatEtaTime(eta)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                widget.leg == DriverNavLeg.toPickup ? 'К точке посадки' : 'К точке высадки',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _busy ? null : primaryAction,
                  child: Text(primaryLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ),
              if (scrollController.hasClients) ...[
                const SizedBox(height: 16),
                Text('Пассажир', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text(_passengerName() ?? '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text('Посадка', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Text(pickup, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text('Высадка', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Text(drop, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => DriverOrderChatScreen(
                                orderId: widget.orderId,
                                passengerName: _passengerName(),
                                passengerPhone: _passengerPhone(),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Чат'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openPhone(_passengerPhone()),
                        icon: const Icon(Icons.phone_outlined),
                        label: const Text('Звонок'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final toLat = _toLat;
    final toLon = _toLon;
    final routePoints = parseRoadRoutePoints(_routePayload);
    final fromLat = _driverLat ?? routePoints?.firstOrNull?.elementAtOrNull(0);
    final fromLon = _driverLon ?? routePoints?.firstOrNull?.elementAtOrNull(1);
    final polyline = routePoints ?? [];

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (toLat != null &&
              toLon != null &&
              fromLat != null &&
              fromLon != null &&
              polyline.isNotEmpty)
            DriverNavigationMap(
              key: ValueKey('${widget.leg.name}-${polyline.length}'),
              fromLat: fromLat,
              fromLon: fromLon,
              toLat: toLat,
              toLon: toLon,
              routePoints: polyline,
              driverLat: _driverLat,
              driverLon: _driverLon,
              driverHeading: _driverHeading,
            )
          else
            ColoredBox(
              color: const Color(0xFFE8E8E8),
              child: Center(
                child: _loadingRoute
                    ? const CircularProgressIndicator(color: _primaryOrange)
                    : const Text('Маршрут недоступен'),
              ),
            ),
          if (_locationDenied)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 72,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Разрешите доступ к геолокации для навигации.',
                    style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                  ),
                ),
              ),
            ),
          Positioned(top: 0, left: 0, right: 0, child: _buildTopBanner()),
          _buildBottomPanel(),
          if (_busy)
            const Positioned.fill(
              child: ModalBarrier(dismissible: false, color: Color(0x33000000)),
            ),
          if (_busy) const Center(child: CircularProgressIndicator(color: _primaryOrange)),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

extension _ElementAtOrNull<E> on List<E> {
  E? elementAtOrNull(int index) {
    if (index < 0 || index >= length) return null;
    return this[index];
  }
}
