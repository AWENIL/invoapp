import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

const _primaryOrange = Color(0xFFFF6B44);

String driverOrderDisplayNo(String id) {
  final parts = id.split('-');
  if (parts.length >= 5) {
    final a = parts[1].length >= 2 ? parts[1].substring(0, 2) : parts[1];
    final b = parts[4].length >= 2 ? parts[4].substring(parts[4].length - 2) : parts[4];
    return '№${a.toUpperCase()}-${b.toUpperCase()}';
  }
  if (id.length <= 12) return '№$id';
  return '№${id.substring(0, 6)}…${id.substring(id.length - 2)}';
}

String _mmSs(int totalSec) {
  final sec = totalSec.clamp(0, 86400);
  final m = sec ~/ 60;
  final s = sec % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class _CategoryDef {
  const _CategoryDef(this.apiValue, this.title, this.subtitle);
  final String apiValue;
  final String title;
  final String subtitle;
}

const _kCategories = <_CategoryDef>[
  _CategoryDef('behavior', 'Поведение', 'Грубость, конфликт, агрессия'),
  _CategoryDef('route_stops', 'Маршрут и точки', 'Просьба об остановке в неположенном месте'),
  _CategoryDef('cabin_cleanliness', 'Чистота в салоне', 'Оставили мусор, испачкали сиденья'),
  _CategoryDef('smoking', 'Курение или вейпинг', 'Использование систем нагревания или сигарет в салоне'),
  _CategoryDef('intoxication', 'Состояние', 'Пассажир в состоянии сильного опьянения'),
  _CategoryDef('other', 'Другое', 'Опишите подробнее'),
];

/// Экран жалобы водителя по маршруту мобильного приложения.
class DriverOrderComplaintScreen extends ConsumerStatefulWidget {
  const DriverOrderComplaintScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<DriverOrderComplaintScreen> createState() => _DriverOrderComplaintScreenState();
}

class _DriverOrderComplaintScreenState extends ConsumerState<DriverOrderComplaintScreen> {
  final _descriptionCtrl = TextEditingController();
  bool _loading = true;
  String? _loadError;
  Map<String, dynamic>? _ctx;
  String? _selected;
  String? _attachmentPath;
  String? _attachmentName;
  bool _busy = false;
  double _previewProgress = 0;

  @override
  void initState() {
    super.initState();
    _selected = _kCategories.first.apiValue;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await ref.read(invoApiProvider).getDriverOrderComplaint(widget.orderId);
      if (!mounted) return;
      setState(() {
        _ctx = data;
        _loading = false;
      });
      final exists = data['complaint_exists'] == true;
      final can = data['can_file'] == true;
      if (exists && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('По этому заказу жалоба уже подана')),
        );
        Navigator.of(context).pop();
        return;
      }
      if (!can && mounted) {
        final reason = data['reason']?.toString() ?? 'Нельзя подать жалобу по этому заказу';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  int get _recordingTotalSec {
    final rec = _ctx?['recording'];
    if (rec is Map) {
      final total = rec['duration_seconds'];
      if (total is num && total > 0) return total.round();
    }
    return 27 * 60 + 35;
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.single;
    final path = f.path;
    if (path == null || path.isEmpty) return;
    setState(() {
      _attachmentPath = path;
      _attachmentName = f.name;
    });
  }

  Future<void> _submit() async {
    final cat = _selected;
    if (cat == null || cat.isEmpty) return;
    final text = _descriptionCtrl.text.trim();
    if (text.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Опишите ситуацию не короче 10 символов')),
      );
      return;
    }
    if (_ctx != null && _ctx!['can_file'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_ctx!['reason']?.toString() ?? 'Нельзя подать жалобу')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(invoApiProvider).submitDriverOrderComplaint(
            widget.orderId,
            category: cat,
            description: text,
            attachmentPath: _attachmentPath,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Жалоба отправлена')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderNo = driverOrderDisplayNo(widget.orderId);
    final totalSec = _recordingTotalSec;
    final playable = (_ctx?['recording'] is Map) &&
        ((_ctx!['recording'] as Map)['playable_url']?.toString().isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Жалоба'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primaryOrange))
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Повторить')),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Поездка $orderNo',
                            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 20),
                          _videoCard(
                            totalSec: totalSec,
                            playable: playable,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Запись с регистратора или салона поможет быстрее разобраться в ситуации. '
                            'Доступ к фрагменту только у службы поддержки',
                            style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Тип проблемы',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1.15,
                            ),
                            itemCount: _kCategories.length,
                            itemBuilder: (context, i) {
                              final c = _kCategories[i];
                              final sel = _selected == c.apiValue;
                              return Material(
                                color: sel ? _primaryOrange : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  onTap: () => setState(() => _selected = c.apiValue),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: sel ? _primaryOrange : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.title,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: sel ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          c.subtitle,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            height: 1.25,
                                            color: sel ? Colors.white70 : Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Описание',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _descriptionCtrl,
                            minLines: 4,
                            maxLines: 8,
                            decoration: InputDecoration(
                              hintText:
                                  'Что произошло, когда и кто участвовал. Минимум 10 символов.',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: _primaryOrange, width: 2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Файл (необязательно)',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _pickFile,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                              side: BorderSide(color: Colors.grey.shade400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: Icon(Icons.attach_file, color: Colors.grey.shade700),
                            label: Text(
                              _attachmentName ?? 'Прикрепить фото или PDF',
                              style: TextStyle(color: Colors.grey.shade800),
                            ),
                          ),
                          if (_attachmentName != null) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _attachmentPath = null;
                                          _attachmentName = null;
                                        }),
                                child: const Text('Убрать файл'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 20, color: Colors.grey.shade600),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Срок подачи — 7 дней',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Material(
                        elevation: 8,
                        color: Colors.white,
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _primaryOrange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                onPressed: (_busy || _ctx?['can_file'] != true) ? null : _submit,
                                child: _busy
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Сообщить о проблеме',
                                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _videoCard({required int totalSec, required bool playable}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 180,
        color: const Color(0xFFE8E8E8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _CabinSilhouettePainter()),
            ),
            Center(
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: playable
                      ? null
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Фрагмент записи доступен только службе поддержки после отправки жалобы.',
                              ),
                            ),
                          );
                        },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(Icons.play_arrow, size: 36, color: _primaryOrange),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 36,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: _previewProgress.clamp(0.0, 1.0),
                      activeColor: _primaryOrange,
                      inactiveColor: Colors.white54,
                      onChanged: playable
                          ? (v) => setState(() => _previewProgress = v)
                          : (v) => setState(() => _previewProgress = v),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 16,
              bottom: 12,
              child: Text(
                '${_mmSs((_previewProgress * totalSec).round())} / ${_mmSs(totalSec)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _primaryOrange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CabinSilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dash = Paint()
      ..color = Colors.grey.shade500
      ..strokeWidth = 2;
    final y = size.height * 0.55;
    canvas.drawLine(Offset(size.width * 0.08, y), Offset(size.width * 0.92, y), dash);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
