import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:permission_handler/permission_handler.dart';

import 'auth/welcome_screen.dart';
import 'providers/app_providers.dart';
import 'providers/driver_profile_extras_providers.dart';
import 'screens/driver_shell.dart';
import 'services/driver_camera_permission.dart';
import 'services/driver_location_sync.dart';
import 'theme/driver_auth_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  runApp(const ProviderScope(child: _DriverPermissionsRoot()));
}

enum _StartupPhase { loading, cameraRequired, ready }

/// Сначала геолокация и обязательная камера, затем вход и основной интерфейс.
class _DriverPermissionsRoot extends ConsumerStatefulWidget {
  const _DriverPermissionsRoot();

  @override
  ConsumerState<_DriverPermissionsRoot> createState() => _DriverPermissionsRootState();
}

class _DriverPermissionsRootState extends ConsumerState<_DriverPermissionsRoot> {
  _StartupPhase _phase = _StartupPhase.loading;
  String? _loadingMessage;
  CameraAccessState _cameraState = CameraAccessState.unknown;

  @override
  void initState() {
    super.initState();
    _primePermissions();
  }

  Future<void> _primePermissions() async {
    setState(() {
      _phase = _StartupPhase.loading;
      _loadingMessage = 'Запрашиваем доступ к геолокации…';
    });
    await DriverLocationSync.primeLocationAtStartup();

    if (!mounted) return;
    setState(() => _loadingMessage = kIsWeb ? 'Проверяем доступ к камере…' : 'Запрашиваем доступ к камере…');
    final cameraOk = await _resolveCameraAtStartup();

    if (!mounted) return;
    setState(() {
      _phase = cameraOk ? _StartupPhase.ready : _StartupPhase.cameraRequired;
      _loadingMessage = null;
    });
  }

  /// На web не вызываем getUserMedia без жеста пользователя — только Permissions API.
  /// Состояние unknown (Permissions API не ответил) — пропускаем в приложение.
  Future<bool> _resolveCameraAtStartup() async {
    if (kIsWeb) {
      _cameraState = await DriverCameraPermission.accessState();
      // granted → в приложение; denied → экран камеры; prompt/unknown → экран камеры
      return _cameraState == CameraAccessState.granted;
    }
    final granted = await DriverCameraPermission.ensureGranted();
    _cameraState = granted
        ? CameraAccessState.granted
        : await DriverCameraPermission.accessState();
    return granted;
  }

  Future<void> _retryCamera() async {
    setState(() {
      _phase = _StartupPhase.loading;
      _loadingMessage = 'Запрашиваем доступ к камере…';
    });
    final cameraOk = await DriverCameraPermission.ensureGranted();
    _cameraState = cameraOk
        ? CameraAccessState.granted
        : await DriverCameraPermission.accessState();
    if (!mounted) return;
    setState(() {
      _phase = cameraOk ? _StartupPhase.ready : _StartupPhase.cameraRequired;
      _loadingMessage = null;
    });
  }

  Future<void> _openCameraSettings(BuildContext context) async {
    if (kIsWeb) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Разрешить камеру в Chrome'),
          content: const Text(
            '1. Нажмите на значок камеры слева от адресной строки (или замок).\n'
            '2. Выберите «Разрешить» для камеры.\n'
            '3. Нажмите «Разрешить камеру» в приложении или обновите страницу.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
          ],
        ),
      );
      return;
    }
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase != _StartupPhase.ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: DriverAuthTheme.material(),
        home: Builder(
          builder: (ctx) {
            if (_phase == _StartupPhase.cameraRequired) {
              return _CameraRequiredScreen(
                cameraState: _cameraState,
                onRetry: _retryCamera,
                onOpenSettings: () => _openCameraSettings(ctx),
              );
            }
            return Scaffold(
              backgroundColor: DriverAuthTheme.material().scaffoldBackgroundColor,
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 24),
                        Text(
                          _loadingMessage ?? 'Подготовка…',
                          textAlign: TextAlign.center,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Геолокация и камера нужны для работы водителя: маршруты, диспетчер и запись салона во время поездки.',
                          textAlign: TextAlign.center,
                          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    final session = ref.watch(sessionProvider);
    final themeMode = ref.watch(driverThemeModeProvider);
    final materialKey = session.when(
      data: (s) {
        if (s == null) return 'auth_stack';
        final id = s.profile['id'];
        return 'driver_${id ?? 'unknown'}';
      },
      loading: () => 'session_loading',
      error: (e, _) => 'session_error',
    );
    return MaterialApp(
      key: ValueKey<String>(materialKey),
      debugShowCheckedModeBanner: false,
      title: 'Invotaxi Водитель',
      theme: DriverAuthTheme.material(),
      darkTheme: DriverAuthTheme.darkMaterial(),
      themeMode: themeMode,
      home: session.when(
        data: (s) => s == null
            ? const DriverWelcomeScreen()
            : const DriverShell(),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      ),
    );
  }
}

class _CameraRequiredScreen extends StatelessWidget {
  const _CameraRequiredScreen({
    required this.cameraState,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final CameraAccessState cameraState;
  final Future<void> Function() onRetry;
  final Future<void> Function() onOpenSettings;

  bool get _isDenied => cameraState == CameraAccessState.denied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: DriverAuthTheme.material().scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Icon(Icons.videocam_off_outlined, size: 72, color: Colors.orange.shade800),
              const SizedBox(height: 24),
              Text(
                _isDenied ? 'Камера заблокирована' : 'Нужен доступ к камере',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                _isDenied && kIsWeb
                    ? 'Chrome запретил камеру для этого сайта. Разрешите её в настройках сайта (значок камеры в адресной строке), затем нажмите кнопку ниже.'
                    : 'Без камеры запись салона не будет работать. Разрешите доступ к камере для полноценной работы приложения.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  height: 1.4,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => onRetry(),
                  child: Text(_isDenied ? 'Проверить снова' : 'Разрешить камеру'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => onOpenSettings(),
                  child: Text(kIsWeb ? 'Как разрешить в Chrome' : 'Открыть настройки'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
