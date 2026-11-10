import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show Rect;
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/one_tap/mit_resilience.dart';
import 'package:hiddify/features/one_tap/report/mit_connection_journal.dart';
import 'package:hiddify/features/one_tap/report/mit_connection_journal_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

export 'mit_connection_journal_provider.dart';

class MitErrorReport {
  const MitErrorReport({required this.text, required this.fileName, required this.hasAttempt});
  final String text;
  final String fileName;
  final bool hasAttempt;
  Uint8List get bytes => Uint8List.fromList(utf8.encode(text));

  factory MitErrorReport.create({required String diagnostic, required MitConnectionAttempt? attempt}) {
    final lines = <String>[
      "Mit's VPN — отчёт об ошибке",
      'Время отчёта (UTC): ${DateTime.now().toUtc().toIso8601String()}',
      '',
      'Состояние приложения:',
      diagnostic,
      '',
      'Последнее подключение:',
    ];
    if (attempt == null) {
      lines.add('Сохранённой попытки нет. Повторите подключение и откройте отчёт ещё раз.');
    } else {
      lines.addAll([
        'ID попытки: ${attempt.id}',
        'Начало (UTC): ${attempt.started.toIso8601String()}',
        'Окончание (UTC): ${attempt.ended?.toIso8601String() ?? 'не зафиксировано'}',
        'Протокол: ${attempt.protocol.name}',
        'Автовосстановление: ${attempt.automatic ? 'да' : 'нет'}',
        'Пропущено старых событий: ${attempt.omitted}',
        '',
        'Журнал последней попытки:',
        for (final e in attempt.events)
          '+${(e.ms / 1000).toStringAsFixed(3)}s [${e.warning ? 'WARN' : 'INFO'}] '
              '[${e.core ? 'core' : 'app'}] ${e.code.name}: ${e.code.title}${e.count > 1 ? ' (×${e.count})' : ''}',
      ]);
    }
    lines.addAll([
      '',
      'Сырые логи, ключи, адреса, имена профилей и посещённые сайты не включены.',
      'Распознанные технические ошибки представлены фиксированными кодами; неизвестный текст скрыт.',
    ]);
    return MitErrorReport(
      text: '${lines.join('\n')}\n',
      fileName: 'mits-vpn-report-${attempt?.id.substring(0, 8) ?? 'status'}.txt',
      hasAttempt: attempt != null,
    );
  }
}

final mitErrorReportProvider = FutureProvider.autoDispose<MitErrorReport>((ref) async {
  final journal = ref.read(mitConnectionJournalProvider);
  final attempt = await journal.snapshot();
  MitVpnEnvironment? environment;
  try {
    environment = await ref.read(mitVpnPlatformProvider).environment().timeout(const Duration(seconds: 2));
  } catch (_) {
    /* An unavailable platform API is shown as unknown, never as a successful check. */
  }
  final diagnostic = mitSafeDiagnosticReport(
    status: ref.read(connectionNotifierProvider).valueOrNull,
    recovery: ref.read(mitRecoveryViewProvider),
    autoRecovery: ref.read(MitResiliencePreferences.autoRecovery),
    backupCount: ref.read(MitResiliencePreferences.backupProfiles).length,
    environment: environment,
  );
  return MitErrorReport.create(diagnostic: diagnostic, attempt: attempt);
});

class MitReportExporter {
  Future<bool> save(MitErrorReport report) async {
    // Android's Storage Access Framework writes the supplied bytes. No broad
    // storage permission or fixed /sdcard path is needed.
    final destination = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить отчёт об ошибке',
      fileName: report.fileName,
      type: FileType.custom,
      allowedExtensions: ['txt'],
      bytes: report.bytes,
    );
    return destination != null;
  }

  Future<void> share(MitErrorReport report, Rect origin) async {
    await Share.shareXFiles(
      [XFile.fromData(report.bytes, mimeType: 'text/plain')],
      fileNameOverrides: [report.fileName],
      subject: "Mit's VPN: отчёт об ошибке",
      sharePositionOrigin: origin,
    );
    // Opening the chooser does not establish delivery to Telegram.
  }
}

final mitReportExporterProvider = Provider<MitReportExporter>((ref) => MitReportExporter());
