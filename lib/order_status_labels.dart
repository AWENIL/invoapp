/// Подписи статусов заказа для UI (совпадают с бэкендом OrderStatus).
String orderStatusLabelRu(String? code) {
  if (code == null || code.isEmpty) return '—';
  switch (code) {
    case 'assigned':
      return 'Назначен';
    case 'driver_en_route':
      return 'Еду к пассажиру';
    case 'arrived_waiting':
      return 'Ожидаю';
    case 'ride_ongoing':
      return 'В пути';
    case 'completed':
      return 'Завершён';
    case 'cancelled':
      return 'Отменён';
    case 'offered':
      return 'Предложен';
    case 'matching':
      return 'Подбор';
    case 'active_queue':
      return 'В очереди';
    case 'submitted':
      return 'Отправлен';
    case 'awaiting_dispatcher_decision':
      return 'Ожидание диспетчера';
    case 'no_show':
      return 'Не вышел';
    case 'incident':
      return 'Инцидент';
    default:
      return code;
  }
}
