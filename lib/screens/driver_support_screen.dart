import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import '../providers/app_providers.dart';
import '../theme/driver_auth_theme.dart';

final _supportFaqProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(invoApiProvider).getFaq();
});

const _fallbackFaq = <Map<String, String>>[
  {
    'question': 'Где именно я должен высадить пассажира?',
    'answer':
        'Максимально близко к доступному входу. Убедитесь, что после вашего отъезда человек не окажется заблокирован бордюром или лужей.',
  },
  {
    'question': 'Что делать, если пассажиру стало плохо во время поездки?',
    'answer':
        'Остановитесь в безопасном месте, вызовите скорую при необходимости и сообщите диспетчеру.',
  },
  {
    'question':
        'Как поступить, если кресло или оборудование повредилось в процессе перевозки?',
    'answer':
        'Зафиксируйте обстановку, не продолжайте поездку при угрозе безопасности и сообщите диспетчеру.',
  },
  {
    'question': 'Что делать, если пассажир не вышел?',
    'answer':
        'Свяжитесь с диспетчером и действуйте по инструкции сервиса; зафиксируйте время ожидания.',
  },
];

Future<void> _callDispatch(BuildContext context) async {
  final raw = dispatchPhoneTelUri.trim();
  if (raw.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Номер диспетчера не настроен (DISPATCH_PHONE_TEL)')),
      );
    }
    return;
  }
  final uri = Uri.parse(raw.startsWith('tel:') ? raw : 'tel:$raw');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось открыть звонок')));
  }
}

class DriverSupportScreen extends ConsumerStatefulWidget {
  const DriverSupportScreen({super.key});

  @override
  ConsumerState<DriverSupportScreen> createState() => _DriverSupportScreenState();
}

class _DriverSupportScreenState extends ConsumerState<DriverSupportScreen> {
  int? _expandedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final faqAsync = ref.watch(_supportFaqProvider);
    final outline = theme.colorScheme.outline.withValues(alpha: 0.35);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Служба поддержки'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: DriverAuthColors.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.headset_mic, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text('24/7', style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Как мы можем помочь?',
                  style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ответим на вопросы о поездках, оплате и аккаунте. Среднее время ответа — 2 минуты.',
                  style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.95), height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: theme.cardTheme.color ?? theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _callDispatch(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: outline),
                ),
                child: Row(
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Написать в чат',
                        style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          faqAsync.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            error: (e, _) => Column(children: _buildFaqList(theme, _fallbackFaq)),
            data: (list) {
              if (list.isEmpty) {
                return Column(children: _buildFaqList(theme, _fallbackFaq));
              }
              return Column(
                children: List.generate(list.length, (i) {
                  final q = list[i]['question']?.toString() ?? '';
                  final a = list[i]['answer']?.toString() ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _faqTile(theme, outline, i, q, a),
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _callDispatch(context),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Связаться с оператором'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFaqList(ThemeData theme, List<Map<String, String>> items) {
    final outline = theme.colorScheme.outline.withValues(alpha: 0.35);
    return List.generate(items.length, (i) {
      final q = items[i]['question'] ?? '';
      final a = items[i]['answer'] ?? '';
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _faqTile(theme, outline, i, q, a),
      );
    });
  }

  Widget _faqTile(ThemeData theme, Color outline, int index, String question, String answer) {
    final expanded = _expandedIndex == index;
    return Material(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() {
            _expandedIndex = expanded ? null : index;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      question,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (expanded && answer.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  answer,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
