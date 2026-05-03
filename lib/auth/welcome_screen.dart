import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../config/env.dart';
import 'legal_launch.dart';
import 'phone_login_screen.dart';
import 'auth_widgets.dart';
import '../theme/driver_auth_theme.dart';

class DriverWelcomeScreen extends StatefulWidget {
  const DriverWelcomeScreen({super.key});

  @override
  State<DriverWelcomeScreen> createState() => _DriverWelcomeScreenState();
}

class _DriverWelcomeScreenState extends State<DriverWelcomeScreen> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer();
    _privacyTap = TapGestureRecognizer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _termsTap.onTap = () => launchLegalUrl(context, termsUrl);
    _privacyTap.onTap = () => launchLegalUrl(context, privacyUrl);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  void _openPhone() {
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => const DriverPhoneLoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: DriverAuthColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 4),
              // Плейсхолдер под логотип / иллюстрацию
              SizedBox(
                height: 120,
                child: Center(
                  child: Icon(
                    Icons.local_taxi_rounded,
                    size: 72,
                    color: DriverAuthColors.secondaryText.withValues(alpha: 0.35),
                  ),
                ),
              ),
              const Spacer(flex: 5),
              DriverAuthPrimaryButton(
                label: 'Войти по номеру телефона',
                onPressed: _openPhone,
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
                      const TextSpan(text: 'Нажимая «Войти», вы соглашаетесь с '),
                      TextSpan(
                        text: 'условиями использования',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: DriverAuthColors.primaryText,
                        ),
                        recognizer: _termsTap,
                      ),
                      const TextSpan(text: ' и '),
                      TextSpan(
                        text: 'политикой конфиденциальности',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: DriverAuthColors.primaryText,
                        ),
                        recognizer: _privacyTap,
                      ),
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
