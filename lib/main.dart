import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'auth/welcome_screen.dart';
import 'providers/app_providers.dart';
import 'providers/driver_profile_extras_providers.dart';
import 'screens/driver_shell.dart';
import 'services/driver_location_sync.dart';
import 'theme/driver_auth_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  runApp(const ProviderScope(child: _DriverGeoFirstRoot()));
}

/// Сначала запрос геолокации, затем загрузка сессии и обычный интерфейс.
class _DriverGeoFirstRoot extends ConsumerStatefulWidget {
  const _DriverGeoFirstRoot();

  @override
  ConsumerState<_DriverGeoFirstRoot> createState() => _DriverGeoFirstRootState();
}

class _DriverGeoFirstRootState extends ConsumerState<_DriverGeoFirstRoot> {
  bool _geoPrimed = false;

  @override
  void initState() {
    super.initState();
    _primeGeo();
  }

  Future<void> _primeGeo() async {
    await DriverLocationSync.primeLocationAtStartup();
    if (mounted) setState(() => _geoPrimed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_geoPrimed) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: DriverAuthTheme.material(),
        home: Builder(
          builder: (ctx) => Scaffold(
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
                        'Запрашиваем доступ к геолокации…',
                        textAlign: TextAlign.center,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Разрешение запрашивается до входа в аккаунт. Геолокация нужна диспетчеру, навигатору и маршрутам к заказу.',
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
          ),
        ),
      );
    }

    final session = ref.watch(sessionProvider);
    final themeMode = ref.watch(driverThemeModeProvider);
    // Сброс стека навигатора при входе: иначе после успешного OTP остаётся маршрут
    // «телефон → код» поверх MaterialApp и главный экран не виден.
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
