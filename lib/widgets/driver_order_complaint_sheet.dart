import 'package:flutter/material.dart';

import '../screens/driver_order_complaint_screen.dart';

/// Открывает полноэкранную форму жалобы по макету приложения.
Future<void> openDriverOrderComplaint(BuildContext context, String orderId) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => DriverOrderComplaintScreen(orderId: orderId),
    ),
  );
}
