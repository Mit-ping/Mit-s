import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/features/one_tap/mit_brand.dart';
import 'package:hiddify/features/one_tap/mit_release.dart';
import 'package:hiddify/features/one_tap/mit_windows_updates.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MitWindowsUpdatesPage extends ConsumerStatefulWidget {
  const MitWindowsUpdatesPage({super.key});
  @override
  ConsumerState<MitWindowsUpdatesPage> createState() => _MitWindowsUpdatesPageState();
}

class _MitWindowsUpdatesPageState extends ConsumerState<MitWindowsUpdatesPage> {
  CancelToken? request;
  MitWindowsUpdate? update;
  File? installer;
  String? message;
  double? progress;
  bool busy = false;
  @override
  void dispose() {
    request?.cancel();
    super.dispose();
  }

  Future<void> check() async {
    final token = CancelToken();
    request = token;
    setState(() {
      busy = true;
      update = null;
      installer = null;
      message = null;
      progress = null;
    });
    try {
      final value = await ref.read(mitWindowsUpdateServiceProvider).check(token);
      if (mounted && !token.isCancelled)
        setState(() {
          update = value;
          message = value == null ? 'Обновлений для Windows не найдено.' : null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () =>
              message = token.isCancelled ? 'Проверка отменена.' : 'Не удалось проверить обновления. Повторите позже.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> download() async {
    final value = update;
    if (value == null || busy) return;
    final token = CancelToken();
    request = token;
    setState(() {
      busy = true;
      progress = 0;
      installer = null;
      message = 'Скачивание установщика…';
    });
    try {
      final service = ref.read(mitWindowsUpdateServiceProvider);
      final file = await service.download(value, await service.directory(), token, (received, total) {
        if (mounted && !token.isCancelled) setState(() => progress = received / total);
      });
      if (mounted && !token.isCancelled)
        setState(() {
          installer = file;
          message = 'Размер и SHA256 проверены. Установка запускается только по вашему нажатию.';
        });
    } catch (_) {
      if (mounted)
        setState(
          () => message = token.isCancelled
              ? 'Скачивание отменено.'
              : 'Файл не скачался или не прошёл проверку. Установка заблокирована.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> install() async {
    final value = update;
    final file = installer;
    if (value == null || file == null || busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Обновить Mit’s VPN?'),
        content: const Text(
          'Windows откроет установщик и может запросить разрешение администратора. Перед установкой отключите VPN и закройте приложение. Цифровая подпись этой бета-сборки не подтверждена.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Открыть установщик')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await ref.read(mitWindowsUpdateServiceProvider).install(value, file);
      if (mounted) setState(() => message = 'Установщик открыт. Закройте Mit’s VPN перед заменой файлов.');
    } catch (_) {
      if (mounted)
        setState(() {
          installer = null;
          message = 'Не удалось проверить или открыть установщик.';
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MitPage(
    title: 'Обновления Windows',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Установлена ${MitRelease.windowsVersion} (${MitRelease.windowsBuild}) · Windows x64'),
        const SizedBox(height: 16),
        const Text(
          'Проверка обновлений из релизов Mit’s VPN запускается вручную. Перед запуском установщика проверяются размер и SHA256; они не заменяют цифровую подпись издателя.',
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: busy ? null : check, child: const Text('Проверить обновления')),
        if (update case final value?) ...[
          const SizedBox(height: 16),
          Text('Доступна ${value.version}'),
          Text(value.notes),
          if (installer == null)
            OutlinedButton(onPressed: busy ? null : download, child: const Text('Скачать установщик')),
          if (installer != null)
            FilledButton(onPressed: busy ? null : install, child: const Text('Установить обновление')),
        ],
        if (busy) ...[
          LinearProgressIndicator(value: progress),
          TextButton(onPressed: () => request?.cancel(), child: const Text('Отменить')),
        ],
        if (message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(message!)),
      ],
    ),
  );
}
