import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> launchLegalUrl(BuildContext context, String url) async {
  if (url.trim().isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка не настроена')),
      );
    }
    return;
  }
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Некорректная ссылка')),
      );
    }
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не удалось открыть ссылку')),
    );
  }
}
