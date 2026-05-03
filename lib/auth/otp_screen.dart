import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import 'auth_widgets.dart';
import '../theme/driver_auth_theme.dart';

class DriverOtpScreen extends ConsumerStatefulWidget {
  const DriverOtpScreen({super.key, required this.phone});

  final String phone;

  @override
  ConsumerState<DriverOtpScreen> createState() => _DriverOtpScreenState();
}

class _DriverOtpScreenState extends ConsumerState<DriverOtpScreen>
    with SingleTickerProviderStateMixin {
  static const int _otpLen = 4;
  static const int _cooldownSec = 30;

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  late final AnimationController _blink;

  Timer? _cooldownTimer;
  int _secondsLeft = _cooldownSec;
  bool _loading = false;
  bool _verifyInFlight = false;
  bool _resendLoading = false;
  bool _wrongCode = false;
  double _shakeOffset = 0;

  String get _otp => _controllers.map((c) => c.text).join();

  bool get _complete => _otp.length == _otpLen;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_otpLen, (_) => TextEditingController());
    _focusNodes = List.generate(_otpLen, (i) {
      final n = FocusNode();
      n.addListener(() {
        if (n.hasFocus) {
          setState(() => _wrongCode = false);
        }
      });
      return n;
    });
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    for (var i = 0; i < _otpLen; i++) {
      _controllers[i].addListener(() => _onDigitChanged(i));
    }

    _startCooldown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes[0].requestFocus();
    });
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsLeft = _cooldownSec);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_secondsLeft <= 1) {
          _secondsLeft = 0;
          t.cancel();
        } else {
          _secondsLeft--;
        }
      });
    });
  }

  void _onDigitChanged(int index) {
    final t = _controllers[index].text;
    if (t.length > 1) {
      final digits = t.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= _otpLen) {
        for (var i = 0; i < _otpLen; i++) {
          _controllers[i].text = digits[i];
        }
        _focusNodes[_otpLen - 1].requestFocus();
      } else {
        _controllers[index].text = digits.isNotEmpty ? digits[0] : '';
      }
    } else if (t.isNotEmpty && index < _otpLen - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
    if (_complete && !_loading && !_verifyInFlight) {
      Future.microtask(() {
        if (mounted && _complete && !_loading && !_verifyInFlight) _verify();
      });
    }
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].selection = TextSelection.collapsed(
        offset: _controllers[index - 1].text.length,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _shake() async {
    const steps = <double>[0, -10, 10, -8, 8, -4, 4, 0];
    for (final o in steps) {
      await Future<void>.delayed(const Duration(milliseconds: 35));
      if (!mounted) return;
      setState(() => _shakeOffset = o);
    }
  }

  String _mapVerifyError(Object e) {
    final s = e is Exception ? e.toString().replaceFirst('Exception: ', '') : '$e';
    final lower = s.toLowerCase();
    if (lower.contains('неверный') ||
        lower.contains('истек') ||
        lower.contains('код должен') ||
        lower.contains('invalid')) {
      return 'Неверный код. Попробуйте еще раз';
    }
    return s;
  }

  Future<void> _verify() async {
    if (!_complete || _loading || _verifyInFlight) return;
    _verifyInFlight = true;
    setState(() {
      _loading = true;
      _wrongCode = false;
    });
    FocusScope.of(context).unfocus();
    try {
      final data = await ref.read(invoApiProvider).verifyOtp(widget.phone, _otp);
      try {
        await ref.read(sessionProvider.notifier).afterVerify(data);
      } catch (e) {
        await ref.read(tokenStorageProvider).clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${e is Exception ? e.toString().replaceFirst('Exception: ', '') : e}\n'
                'Код на сервере уже израсходован. Нажмите «Отправить код повторно».',
              ),
            ),
          );
        }
        return;
      }
    } catch (e) {
      final raw = e is Exception ? e.toString() : e.toString();
      final lower = raw.toLowerCase();
      final badOtp = lower.contains('неверный') ||
          lower.contains('истек') ||
          lower.contains('invalid') ||
          lower.contains('код должен');
      final phoneFormat = lower.contains('телефон') || lower.contains('phone');
      if (phoneFormat && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mapVerifyError(e))),
        );
      } else if (badOtp && mounted) {
        setState(() => _wrongCode = true);
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
        await _shake();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mapVerifyError(e))),
        );
      }
    } finally {
      _verifyInFlight = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  /// После ошибки verifyOtp токен мог не сохраниться; при успехе without exception we're good.
  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resendLoading) return;
    setState(() {
      _resendLoading = true;
      _wrongCode = false;
    });
    try {
      await ref.read(invoApiProvider).requestOtp(widget.phone);
      if (!mounted) return;
      for (final c in _controllers) {
        c.clear();
      }
      _startCooldown();
      _focusNodes[0].requestFocus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is Exception ? e.toString().replaceFirst('Exception: ', '') : '$e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _resendLoading = false);
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    _blink.dispose();
    super.dispose();
  }

  Widget _digitCell(int i) {
    final focused = _focusNodes[i].hasFocus;
    Color borderColor = DriverAuthColors.border;
    if (_wrongCode) {
      borderColor = DriverAuthColors.error;
    } else if (focused) {
      borderColor = DriverAuthColors.primary;
    }

    return Focus(
      onKeyEvent: (node, event) => _onKey(i, event),
      child: Container(
        width: 60,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: focused || _wrongCode ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: TextField(
          controller: _controllers[i],
          focusNode: _focusNodes[i],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: DriverAuthColors.primaryText,
          ),
          cursorColor: DriverAuthColors.primary,
          cursorWidth: 2,
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          showCursor: true,
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }

  String get _timerLabel {
    final s = _secondsLeft;
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const DriverAuthBackButton(),
              const SizedBox(height: 28),
              Text(
                'Введите СМС-код',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: DriverAuthColors.primaryText,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Мы отправили SMS на номер ${widget.phone}',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: DriverAuthColors.secondaryText,
                ),
              ),
              const SizedBox(height: 36),
              Transform.translate(
                offset: Offset(_shakeOffset, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _otpLen; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          _digitCell(i),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (_wrongCode) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.error_outline, size: 18, color: DriverAuthColors.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Неверный код. Попробуйте еще раз',
                        style: TextStyle(
                          color: DriverAuthColors.error,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Center(
                child: _secondsLeft > 0
                    ? FadeTransition(
                        opacity: Tween<double>(begin: 0.85, end: 1).animate(
                          CurvedAnimation(parent: _blink, curve: Curves.easeInOut),
                        ),
                        child: Text(
                          'Отправить код повторно через $_timerLabel',
                          style: TextStyle(
                            fontSize: 14,
                            color: DriverAuthColors.secondaryText,
                          ),
                        ),
                      )
                    : TextButton(
                        onPressed: _resendLoading ? null : _resend,
                        child: _resendLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(
                                'Отправить код повторно',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: DriverAuthColors.primaryText,
                                ),
                              ),
                      ),
              ),
              const Spacer(),
              DriverAuthPrimaryButton(
                label: 'Подтвердить',
                loading: _loading,
                enabled: _complete,
                onPressed: _complete && !_loading ? _verify : null,
              ),
              SizedBox(height: 16 + bottom),
            ],
          ),
        ),
      ),
    );
  }
}
