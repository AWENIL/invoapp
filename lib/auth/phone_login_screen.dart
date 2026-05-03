import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../providers/app_providers.dart';
import 'auth_widgets.dart';
import 'legal_launch.dart';
import 'otp_screen.dart';
import '../theme/driver_auth_theme.dart';

class DriverPhoneLoginScreen extends ConsumerStatefulWidget {
  const DriverPhoneLoginScreen({super.key});

  @override
  ConsumerState<DriverPhoneLoginScreen> createState() => _DriverPhoneLoginScreenState();
}

class _DriverPhoneLoginScreenState extends ConsumerState<DriverPhoneLoginScreen> {
  final _phone = TextEditingController(text: '+7');
  bool _loading = false;
  String? _error;
  late final TapGestureRecognizer _termsTap;

  static bool _digitsValid(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    return d.length >= 10;
  }

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer();
    _phone.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _termsTap.onTap = () => launchLegalUrl(context, termsUrl);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_digitsValid(_phone.text)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(invoApiProvider);
      final rawPhone = _phone.text.trim();
      await api.requestOtp(rawPhone, forDriver: true);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        CupertinoPageRoute<void>(
          builder: (context) => DriverOtpScreen(phone: rawPhone),
        ),
      );
    } catch (e) {
      final msg = e is Exception ? e.toString().replaceFirst('Exception: ', '') : '$e';
      setState(() => _error = msg);
      if (!mounted) return;
      if (msg.toLowerCase().contains('не найден')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _digitsValid(_phone.text);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: DriverAuthColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      const DriverAuthBackButton(),
                      const SizedBox(height: 28),
                      Text(
                        'Ваш номер',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: DriverAuthColors.primaryText,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Вход только для водителей, заведённых диспетчером. '
                        'Тот же номер в приложении пассажира работает как пассажир — это другой тип аккаунта.',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: DriverAuthColors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]*')),
                        ],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: DriverAuthColors.primaryText,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: DriverAuthColors.background,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: DriverAuthColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: DriverAuthColors.primary, width: 1.5),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: DriverAuthColors.border),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(color: DriverAuthColors.error, fontSize: 14),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              DriverAuthPrimaryButton(
                label: 'Получить код',
                loading: _loading,
                enabled: valid,
                onPressed: valid && !_loading ? _sendOtp : null,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: EdgeInsets.only(bottom: 8 + bottom),
                child: Text.rich(
                  textAlign: TextAlign.center,
                  TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: DriverAuthColors.secondaryText,
                    ),
                    children: [
                      const TextSpan(text: 'Регистрируясь, вы соглашаетесь с '),
                      TextSpan(
                        text: 'условиями использования',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: DriverAuthColors.primaryText,
                        ),
                        recognizer: _termsTap,
                      ),
                      const TextSpan(text: ' и передачи данных.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
