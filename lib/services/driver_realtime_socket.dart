import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/env.dart';

/// `/ws/drivers/<id>/?token=` — `queue_updated`, `order_update`, `new_order`.
class DriverRealtimeSocket {
  WebSocketChannel? _channel;

  void connect({
    required String driverId,
    required String token,
    required void Function(Map<String, dynamic> message) onMessage,
  }) {
    disconnect();
    final base =
        wsBaseUrl.endsWith('/') ? wsBaseUrl.substring(0, wsBaseUrl.length - 1) : wsBaseUrl;
    final uri = Uri.parse(
      '$base/ws/drivers/$driverId/?token=${Uri.encodeQueryComponent(token)}',
    );
    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen(
      (dynamic raw) {
        try {
          final m = jsonDecode(raw as String) as Map<String, dynamic>;
          onMessage(m);
        } catch (_) {}
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
