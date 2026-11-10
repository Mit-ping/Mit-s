import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/one_tap/report/mit_error_report.dart';
import 'package:hiddify/features/one_tap/report/mit_error_report_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Exporter extends MitReportExporter {
  int saves = 0, shares = 0;
  bool cancel = false, fail = false;
  Completer<void>? gate;
  MitErrorReport? sent;
  @override
  Future<bool> save(MitErrorReport report) async {
    saves++;
    sent = report;
    if (fail) throw StateError('private-platform-error');
    return !cancel;
  }

  @override
  Future<void> share(MitErrorReport report, Rect origin) async {
    shares++;
    sent = report;
    if (fail) throw StateError('private-platform-error');
    if (gate != null) await gate!.future;
  }
}

void main() {
  const report = MitErrorReport(text: 'safe-report-preview', fileName: 'mits-vpn-report-test.txt', hasAttempt: true);
  Future<void> open(WidgetTester tester, _Exporter exporter) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mitErrorReportProvider.overrideWith((ref) async => report),
          mitReportExporterProvider.overrideWithValue(exporter),
        ],
        child: const MaterialApp(home: MitErrorReportPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('preview, saved bytes and sharing use the same frozen report', (tester) async {
    final exporter = _Exporter();
    await open(tester, exporter);
    expect(find.text(report.text), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mit-save-report')));
    await tester.pumpAndSettle();
    expect(exporter.sent, same(report));
    expect(find.text('Отчёт сохранён. Можно поделиться им в Telegram.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mit-share-report')));
    await tester.pumpAndSettle();
    expect(exporter.shares, 1);
    expect(exporter.sent!.fileName, report.fileName);
    expect(find.textContaining('отправлен'), findsNothing);
  });

  testWidgets('cancel is not success; errors hide platform text and allow retry', (tester) async {
    final exporter = _Exporter()..cancel = true;
    await open(tester, exporter);
    await tester.tap(find.byKey(const ValueKey('mit-save-report')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Отчёт сохранён'), findsNothing);
    exporter.fail = true;
    await tester.tap(find.byKey(const ValueKey('mit-share-report')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось открыть отправку'), findsOneWidget);
    expect(find.textContaining('private-platform-error'), findsNothing);
    exporter.fail = false;
    await tester.tap(find.byKey(const ValueKey('mit-share-report')));
    await tester.pumpAndSettle();
    expect(exporter.shares, 2);
  });

  testWidgets('export buttons cannot start overlapping file pickers', (tester) async {
    final exporter = _Exporter()..gate = Completer<void>();
    await open(tester, exporter);
    await tester.tap(find.byKey(const ValueKey('mit-share-report')));
    await tester.pump();
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('mit-save-report'))).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('mit-share-report'))).onPressed, isNull);
    exporter.gate!.complete();
    await tester.pumpAndSettle();
    expect(exporter.shares, 1);
  });
}
