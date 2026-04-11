import 'dart:async';

import 'package:flutter/material.dart';

/// Обратный отсчёт 20 минут с [arrivedWaitingAt] (поле заказа с сервера).
class ArrivedWaitingTimer extends StatefulWidget {
  const ArrivedWaitingTimer({super.key, required this.arrivedWaitingAt});

  final DateTime arrivedWaitingAt;

  static const Duration window = Duration(minutes: 20);

  @override
  State<ArrivedWaitingTimer> createState() => _ArrivedWaitingTimerState();
}

class _ArrivedWaitingTimerState extends State<ArrivedWaitingTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end = widget.arrivedWaitingAt.add(ArrivedWaitingTimer.window);
    final now = DateTime.now();
    final left = end.difference(now);
    final remaining = left.isNegative ? Duration.zero : left;
    final totalSec = remaining.inSeconds;
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    final expired = left.isNegative;

    Color bg;
    Color fg;
    if (expired) {
      bg = theme.colorScheme.errorContainer;
      fg = theme.colorScheme.onErrorContainer;
    } else if (totalSec <= 5 * 60) {
      bg = theme.colorScheme.tertiaryContainer;
      fg = theme.colorScheme.onTertiaryContainer;
    } else {
      bg = theme.colorScheme.primaryContainer;
      fg = theme.colorScheme.onPrimaryContainer;
    }

    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(expired ? Icons.timer_off_outlined : Icons.timer_outlined, color: fg, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expired ? 'Время ожидания истекло' : 'Ожидание пассажира',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    expired
                        ? 'Лимит 20 минут — можно начать поездку или оформить по правилам сервиса'
                        : 'Осталось ${_two(m)}:${_two(s)} из 20 мин',
                    style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
