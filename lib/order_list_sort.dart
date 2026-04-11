/// Сортировка списка заказов водителя: срочные активные сверху, затем по времени подачи;
/// завершённые/отменённые — новее выше.
void sortDriverOrders(List<Map<String, dynamic>> orders) {
  DateTime? parseDt(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  int statusRank(String s) {
    switch (s) {
      case 'ride_ongoing':
        return 0;
      case 'arrived_waiting':
        return 1;
      case 'driver_en_route':
        return 2;
      case 'assigned':
        return 3;
      case 'completed':
      case 'cancelled':
        return 10;
      default:
        return 5;
    }
  }

  orders.sort((a, b) {
    final sa = a['status']?.toString() ?? '';
    final sb = b['status']?.toString() ?? '';
    final ra = statusRank(sa);
    final rb = statusRank(sb);
    if (ra != rb) return ra.compareTo(rb);

    if (ra == 10 && rb == 10) {
      final ca = parseDt(a['created_at']);
      final cb = parseDt(b['created_at']);
      if (ca != null && cb != null) return cb.compareTo(ca);
      if (ca != null) return -1;
      if (cb != null) return 1;
      return 0;
    }

    final ta = parseDt(a['desired_pickup_time']);
    final tb = parseDt(b['desired_pickup_time']);
    if (ta != null && tb != null) return ta.compareTo(tb);
    if (ta != null) return -1;
    if (tb != null) return 1;

    final ca = parseDt(a['created_at']);
    final cb = parseDt(b['created_at']);
    if (ca != null && cb != null) return ca.compareTo(cb);
    return 0;
  });
}
