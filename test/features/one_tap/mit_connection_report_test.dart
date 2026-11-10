import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/one_tap/report/mit_connection_journal.dart';
import 'package:hiddify/features/one_tap/report/mit_error_report.dart';
import 'package:logging/logging.dart';

void main() {
  test('only the last attempt is exported; native secrets and destinations never persist', () async {
    final directory = await Directory.systemTemp.createTemp('mits-report-test-');
    final file = File('${directory.path}/last.json');
    final journal = MitConnectionJournal(file: () async => file);
    addTearDown(() async {
      journal.dispose();
      await journal.flush();
      await directory.delete(recursive: true);
    });
    journal.begin(protocol: MitReportProtocol.vlessReality, automatic: false);
    journal.recordError('obsolete connection refused');
    journal.finish(MitReportCode.failed);
    journal.begin(protocol: MitReportProtocol.amneziaWG, automatic: true);
    final logger = Logger('core.service');
    logger.warning(
      'TLS handshake failure for vless://private-uuid@secret.example:443 '
      'PrivateKey=secret-value server=192.0.2.42 visits.example /private/path',
    );
    journal.recordError('unknown-private-secret-value');
    journal.finish(MitReportCode.failed);
    logger.warning('connection refused from a different connection');
    await journal.flush();
    final stored = await file.readAsString();
    final attempt = (await journal.snapshot())!;
    final report = MitErrorReport.create(diagnostic: '{"platform":"Android"}', attempt: attempt);
    expect(attempt.protocol, MitReportProtocol.amneziaWG);
    expect(attempt.events.map((e) => e.code), [
      MitReportCode.start,
      MitReportCode.tls,
      MitReportCode.unknown,
      MitReportCode.failed,
    ]);
    expect(report.text, contains('tls: Ошибка TLS'));
    for (final secret in [
      'secret-value',
      'secret.example',
      '192.0.2.42',
      'visits.example',
      '/private/path',
      'private-uuid',
    ]) {
      expect(stored, isNot(contains(secret)));
      expect(report.text, isNot(contains(secret)));
    }
    expect(utf8.decode(report.bytes), report.text);
    expect(report.fileName, endsWith('.txt'));
    final restored = MitConnectionJournal(file: () async => file, listen: false);
    addTearDown(() async {
      restored.dispose();
      await restored.flush();
    });
    final before = await restored.snapshot();
    Logger('core.service').warning('connection refused during a later app startup');
    expect((await restored.snapshot())!.toJson(), before!.toJson());
    expect((await restored.snapshot())!.toJson(), attempt.toJson());
  });

  test('a new attempt survives a delayed disk read of the previous session', () async {
    final directory = await Directory.systemTemp.createTemp('mits-report-race-');
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}/last.json');
    final previous = MitConnectionJournal(listen: false);
    addTearDown(previous.dispose);
    previous.begin(protocol: MitReportProtocol.vlessReality, automatic: false);
    await target.writeAsString(jsonEncode((await previous.snapshot())!.toJson()));
    final gate = Completer<File>();
    final journal = MitConnectionJournal(file: () => gate.future, listen: false);
    addTearDown(journal.dispose);
    journal.begin(protocol: MitReportProtocol.amneziaWG, automatic: true);
    gate.complete(target);
    expect((await journal.snapshot())!.protocol, MitReportProtocol.amneziaWG);
    await journal.flush();
  });

  test('history is bounded, retains the start and latest error, and is frozen for export', () async {
    var now = DateTime.utc(2026);
    final journal = MitConnectionJournal(now: () => now, listen: false);
    addTearDown(journal.dispose);
    journal.begin(protocol: MitReportProtocol.unknown, automatic: false);
    for (var i = 0; i < 1000; i++) {
      now = now.add(const Duration(milliseconds: 2));
      journal.add(i.isEven ? MitReportCode.timeout : MitReportCode.dns);
    }
    final snapshot = (await journal.snapshot())!;
    expect(snapshot.events.length, 200);
    expect(snapshot.events.first.code, MitReportCode.start);
    expect(snapshot.omitted, greaterThan(0));
    journal.finish(MitReportCode.failed);
    expect(snapshot.complete, isFalse);
    expect((await journal.snapshot())!.events.last.code, MitReportCode.failed);
    expect(utf8.encode(jsonEncode(snapshot.toJson())).length, lessThan(65536));
  });

  test('corrupt or unknown stored content is never copied into a report', () async {
    final directory = await Directory.systemTemp.createTemp('mits-report-corrupt-');
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}/last.json');
    await target.writeAsString('{"id":"private-key"}');
    final journal = MitConnectionJournal(file: () async => target, listen: false);
    addTearDown(journal.dispose);
    expect(await journal.snapshot(), isNull);
    final report = MitErrorReport.create(diagnostic: '{}', attempt: await journal.snapshot());
    expect(report.hasAttempt, isFalse);
    expect(report.text, contains('Сохранённой попытки нет'));
    expect(report.text, isNot(contains('private-key')));
  });

  test('common connection failures map to actionable fixed events', () {
    for (final entry in <String, MitReportCode>{
      'no such host': MitReportCode.dns,
      'context deadline exceeded': MitReportCode.timeout,
      'connection refused': MitReportCode.refused,
      'network is unreachable': MitReportCode.unreachable,
      'x509 unknown authority': MitReportCode.tls,
      'VPN permission denied': MitReportCode.permission,
      'start inbound/tun[tun-in]': MitReportCode.tun,
      'invalid config': MitReportCode.config,
      'authentication failed': MitReportCode.authentication,
    }.entries) {
      expect(MitConnectionJournal.classify(entry.key), entry.value);
    }
  });
}
