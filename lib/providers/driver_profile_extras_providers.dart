import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Тёмная тема вкладок приложения (после входа).
final driverThemeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

class DriverNotificationEntry {
  const DriverNotificationEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
  });

  final String id;
  final String title;
  final String body;
  final IconData icon;
}

List<DriverNotificationEntry> _seedDriverNotifications() {
  return const [
    DriverNotificationEntry(
      id: '1',
      title: 'Обновление приложения',
      body: 'Добавлен геофенс прибытия и таймер ожидания.',
      icon: Icons.schedule_rounded,
    ),
    DriverNotificationEntry(
      id: '2',
      title: 'Новый отзыв',
      body: '«Очень внимательный водитель, помог сесть и пристегнул ремень»',
      icon: Icons.star_rounded,
    ),
    DriverNotificationEntry(
      id: '3',
      title: 'Поездка завершена',
      body: 'Запись салона успешно загружена. Спасибо за работу.',
      icon: Icons.check_circle_outline_rounded,
    ),
    DriverNotificationEntry(
      id: '4',
      title: 'Документы проверены',
      body: 'Все документы подтверждены. Вы можете выходить на линию.',
      icon: Icons.description_outlined,
    ),
  ];
}

final driverNotificationsProvider =
    StateProvider<List<DriverNotificationEntry>>((ref) => _seedDriverNotifications());
