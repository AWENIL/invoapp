import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_providers.dart';
import '../services/order_realtime_socket.dart';
import '../theme/invo_theme.dart';

/// Чат с пассажиром по активному заказу (REST + WebSocket как у пассажира).
class DriverOrderChatScreen extends ConsumerStatefulWidget {
  const DriverOrderChatScreen({
    super.key,
    required this.orderId,
    this.passengerName,
    this.passengerPhone,
  });

  final String orderId;
  final String? passengerName;
  final String? passengerPhone;

  @override
  ConsumerState<DriverOrderChatScreen> createState() => _DriverOrderChatScreenState();
}

class _DriverOrderChatScreenState extends ConsumerState<DriverOrderChatScreen> {
  final OrderRealtimeSocket _sock = OrderRealtimeSocket();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _msgs = [];
  final Set<String> _seenIds = {};
  bool _loading = true;
  String? _loadError;
  bool _sending = false;

  static const List<String> _quick = [
    'Прибуду через 5 минут',
    'Уже на месте',
    'Подожду минуту',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _sock.disconnect();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int _compareCreated(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    final tb = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    return ta.compareTo(tb);
  }

  void _ingest(Map<String, dynamic> data, {bool scrollEnd = false}) {
    final id = data['id']?.toString();
    if (id == null || id.isEmpty) return;
    if (_seenIds.contains(id)) return;
    _seenIds.add(id);
    _msgs.add(data);
    _msgs.sort(_compareCreated);
    setState(() {});
    if (scrollEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _bootstrap() async {
    final api = ref.read(invoApiProvider);
    try {
      final list = await api.getDriverOrderMessages(widget.orderId);
      if (!mounted) return;
      for (final m in list) {
        _ingest(m);
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }

    final token = await ref.read(tokenStorageProvider).readAccess();
    if (token != null && token.isNotEmpty) {
      _sock.connect(
        orderId: widget.orderId,
        token: token,
        onMessage: (msg) {
          if (msg['type']?.toString() != 'chat_message') return;
          final d = msg['data'];
          if (d is! Map) return;
          if (!mounted) return;
          _ingest(Map<String, dynamic>.from(d), scrollEnd: true);
        },
      );
    }

    if (mounted) {
      setState(() => _loading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() => _sending = true);
    FocusScope.of(context).unfocus();
    try {
      final api = ref.read(invoApiProvider);
      final data = await api.postDriverOrderMessage(widget.orderId, text);
      if (!mounted) return;
      _ingest(data, scrollEnd: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Uri? _telUri(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final d = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (d.isEmpty) return null;
    return Uri(scheme: 'tel', path: d.startsWith('+') ? d : d);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.passengerName?.trim();
    final timeFmt = DateFormat('HH:mm');

    return Scaffold(
      backgroundColor: InvoTheme.bg,
      appBar: AppBar(
        title: Text(title?.isNotEmpty == true ? title! : 'Пассажир'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: 'Позвонить пассажиру',
              icon: CircleAvatar(
                backgroundColor: InvoTheme.accent,
                foregroundColor: Colors.black87,
                radius: 20,
                child: const Icon(Icons.phone, size: 20),
              ),
              onPressed: () async {
                final u = _telUri(widget.passengerPhone);
                if (u != null && await canLaunchUrl(u)) await launchUrl(u);
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loadError != null)
            Material(
              color: Colors.red.shade900.withValues(alpha: 0.25),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.red.shade300),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_loadError!, style: TextStyle(color: Colors.red.shade200, fontSize: 13))),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: InvoTheme.accent))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    itemCount: _msgs.length + 2,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Center(
                            child: Text(
                              'Сегодня',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                            ),
                          ),
                        );
                      }
                      final idx = i - 1;
                      if (idx == _msgs.length) return const SizedBox(height: 8);
                      final m = _msgs[idx];
                      final isMine = m['sender']?.toString() == 'driver';
                      final bubble = Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Align(
                          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: isMine ? InvoTheme.accent.withValues(alpha: 0.95) : InvoTheme.surface,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomLeft: Radius.circular(isMine ? 14 : 4),
                                  bottomRight: Radius.circular(isMine ? 4 : 14),
                                ),
                                border: isMine ? null : Border.all(color: Colors.white12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      m['text']?.toString() ?? '',
                                      style: TextStyle(
                                        color: isMine ? Colors.black87 : Colors.white,
                                        height: 1.35,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      () {
                                        final dt =
                                            DateTime.tryParse(m['created_at']?.toString() ?? '')?.toLocal();
                                        return dt != null ? timeFmt.format(dt) : '';
                                      }(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isMine ? Colors.black54 : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                      return bubble;
                    },
                  ),
          ),
          Container(
            color: InvoTheme.surface,
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 10,
              top: 8,
              left: 12,
              right: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _quick.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, qi) {
                      return ActionChip(
                        label: Text(_quick[qi], style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: const Color(0xFF2A2A32),
                        side: const BorderSide(color: Colors.white24),
                        onPressed: () {
                          final q = _quick[qi];
                          setState(() {
                            _input.text = _input.text.isEmpty ? q : '${_input.text.trim()} $q';
                          });
                          _input.selection = TextSelection.collapsed(offset: _input.text.length);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        style: const TextStyle(color: Colors.white),
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Сообщение пассажиру',
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          filled: true,
                          fillColor: const Color(0xFF2A2A32),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: InvoTheme.accent,
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                              )
                            : const Icon(Icons.send_rounded, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
