import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

class EditDriverProfileScreen extends ConsumerStatefulWidget {
  const EditDriverProfileScreen({super.key, required this.initialProfile});

  final Map<String, dynamic> initialProfile;

  @override
  ConsumerState<EditDriverProfileScreen> createState() => _EditDriverProfileScreenState();
}

class _EditDriverProfileScreenState extends ConsumerState<EditDriverProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _carModel;
  late final TextEditingController _plate;
  late final TextEditingController _capacity;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _name = TextEditingController(text: p['name']?.toString() ?? '');
    _carModel = TextEditingController(text: p['car_model']?.toString() ?? '');
    _plate = TextEditingController(text: p['plate_number']?.toString() ?? '');
    _capacity = TextEditingController(
      text: p['capacity'] != null ? '${p['capacity']}' : '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _carModel.dispose();
    _plate.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final cap = int.tryParse(_capacity.text.trim());
    if (cap == null || cap < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите вместимость (целое число от 1)')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(invoApiProvider).patchDriverProfile({
        'name': _name.text.trim(),
        'car_model': _carModel.text.trim(),
        'plate_number': _plate.text.trim(),
        'capacity': cap,
      });
      await ref.read(sessionProvider.notifier).refreshProfile();
      ref.invalidate(driverStatisticsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Редактирование')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'ФИО'),
              textCapitalization: TextCapitalization.words,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Введите имя';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _carModel,
              decoration: const InputDecoration(labelText: 'Модель автомобиля'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Укажите модель';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _plate,
              decoration: const InputDecoration(labelText: 'Госномер'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Укажите номер';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _capacity,
              decoration: const InputDecoration(labelText: 'Вместимость (мест)'),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Укажите вместимость';
                if (int.tryParse(v.trim()) == null) return 'Целое число';
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
