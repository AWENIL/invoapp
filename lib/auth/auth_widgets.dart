import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/driver_auth_theme.dart';

/// Кнопка «назад» как на макете: квадрат со скруглением и серой обводкой.
class DriverAuthBackButton extends StatelessWidget {
  const DriverAuthBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DriverAuthColors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed ?? () => Navigator.of(context).maybePop(),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DriverAuthColors.backButtonBorder),
          ),
          child: Icon(
            CupertinoIcons.chevron_left,
            size: 20,
            color: DriverAuthColors.primaryText,
          ),
        ),
      ),
    );
  }
}

/// Основная CTA с сильным скруглением (как на макетах).
class DriverAuthPrimaryButton extends StatelessWidget {
  const DriverAuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading && onPressed != null;
    return Material(
      color: active ? DriverAuthColors.primary : DriverAuthColors.buttonDisabledFill,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: active ? onPressed : null,
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.white24,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
