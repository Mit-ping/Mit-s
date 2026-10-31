import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/one_tap/vpn_profile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final mitProfileFileLoaderProvider = Provider<Future<String?> Function()>((ref) => pickVpnProfileFile);

Future<String> readVpnProfileText(Stream<List<int>> stream) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (chunk.length > maxVpnProfileBytes - bytes.length) throw const FormatException('Слишком большой профиль.');
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}

Future<String?> pickVpnProfileFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom, allowedExtensions: ['conf', 'txt'],
    allowMultiple: false, withData: false, withReadStream: true,
  );
  if (result == null) return null;
  try {
    final picked = result.files.single;
    if (picked.size > maxVpnProfileBytes) throw const FormatException('Слишком большой профиль.');
    final stream = picked.readStream ?? (picked.path == null ? null : File(picked.path!).openRead());
    if (stream == null) throw const FormatException('Не удалось прочитать профиль.');
    return await readVpnProfileText(stream);
  } finally {
    // Removes the picker's temporary copies, never the document-provider original.
    try { await FilePicker.platform.clearTemporaryFiles(); } catch (_) {}
  }
}

class MitProfileImportDialog extends ConsumerStatefulWidget {
  const MitProfileImportDialog({super.key});

  @override
  ConsumerState<MitProfileImportDialog> createState() => _MitProfileImportDialogState();
}

class _MitProfileImportDialogState extends ConsumerState<MitProfileImportDialog> {
  final controller = TextEditingController();
  bool reading = false;
  String? error;

  Future<void> load(Future<String?> Function() reader) async {
    if (reading) return;
    setState(() { reading = true; error = null; });
    try {
      final text = await reader();
      if (!mounted || text == null) return;
      if (text.length > maxVpnProfileBytes || utf8.encode(text).length > maxVpnProfileBytes) {
        throw const FormatException('Слишком большой профиль.');
      }
      // Programmatic paste preserves .conf newlines in this masked single-line
      // field; the platform's default single-line paste would strip them.
      controller.text = text;
    } catch (_) {
      if (mounted) setState(() { error = 'Не удалось прочитать профиль. Используйте текстовый файл .conf или .txt до 64 КБ.'; });
    } finally {
      if (mounted) setState(() { reading = false; });
    }
  }

  @override
  void dispose() { controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Профиль VPN'),
    scrollable: true,
    content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Вставьте клиентский ключ vpn:// из Amnezia, ссылку awg:// или VLESS + REALITY. Для AWG также доступен файл .conf.'),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('mit-profile-input'),
        controller: controller, obscureText: true, autocorrect: false, enableSuggestions: false,
        enableIMEPersonalizedLearning: false, keyboardType: TextInputType.multiline,
        inputFormatters: [LengthLimitingTextInputFormatter(maxVpnProfileBytes)],
        decoration: const InputDecoration(labelText: 'Ссылка или конфигурация'),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        TextButton.icon(key: const ValueKey('mit-paste-profile'), onPressed: reading ? null : () => load(() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text),
          icon: const Icon(Icons.content_paste), label: const Text('Вставить')),
        TextButton.icon(key: const ValueKey('mit-pick-profile'), onPressed: reading ? null : () => load(ref.read(mitProfileFileLoaderProvider)),
          icon: const Icon(Icons.upload_file_outlined), label: const Text('Из файла')),
      ]),
      if (reading) const Text('Чтение профиля…'),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 8),
      const Text('Ключ скрыт. Маршрутизация и DNS — по настройкам Mit’s VPN.', style: TextStyle(fontSize: 12)),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      TextButton(onPressed: reading ? null : () => Navigator.pop(context, controller.text), child: const Text('Добавить')),
    ],
  );
}
