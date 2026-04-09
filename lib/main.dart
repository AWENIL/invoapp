import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/app_providers.dart';
import 'screens/driver_shell.dart';
import 'screens/login_screen.dart';
import 'theme/invo_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: InvoDriverApp()));
}

class InvoDriverApp extends ConsumerWidget {
  const InvoDriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return MaterialApp(
      title: 'Invotaxi Водитель',
      theme: InvoTheme.dark(),
      home: session.when(
        data: (s) => s == null ? const LoginScreen() : const DriverShell(),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      ),
    );
  }
}
