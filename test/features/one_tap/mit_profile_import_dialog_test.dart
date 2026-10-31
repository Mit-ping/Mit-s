import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/one_tap/mit_profile_import_dialog.dart';
import 'package:hiddify/features/one_tap/vpn_profile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'fixtures/awg_fixture.dart';

void main() {
  Future<void> open(WidgetTester tester, {required Future<String?> Function() loader, required ValueChanged<String?> result}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [mitProfileFileLoaderProvider.overrideWithValue(loader)],
      child: MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
        child: const Text('Открыть'),
        onPressed: () async => result(await showDialog<String>(context: context, builder: (_) => const MitProfileImportDialog())),
      )))),
    ));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
  }

  testWidgets('explicit clipboard paste keeps complete conf while hiding credentials and never reads automatically', (tester) async {
    var reads = 0;
    String? imported;
    final text = awgTestConfig();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') { reads++; return {'text': text}; }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await open(tester, loader: () async => null, result: (value) => imported = value);
    expect(reads, 0);
    await tester.tap(find.byKey(const ValueKey('mit-paste-profile')));
    await tester.pumpAndSettle();
    expect(reads, 1);
    final input = tester.widget<TextField>(find.byKey(const ValueKey('mit-profile-input')));
    expect(input.obscureText, true);
    expect(input.enableIMEPersonalizedLearning, false);
    expect(input.controller!.text, text);
    expect(tester.widget<EditableText>(find.byType(EditableText)).obscureText, true);
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    expect(imported, text);
    expect(prepareVpnProfile(imported!).protocol, MitVpnProtocol.amneziaWg);
  });

  testWidgets('file import keeps the conf intact and cancellation does not import', (tester) async {
    String? imported;
    await open(tester, loader: () async => awgTestConfig(), result: (value) => imported = value);
    await tester.tap(find.byKey(const ValueKey('mit-pick-profile')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('mit-profile-input'))).controller!.text, awgTestConfig());
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(imported, null);
  });

  testWidgets('file reader errors do not show paths or credentials', (tester) async {
    await open(tester, loader: () async => throw StateError('private/path/${testWgKey(1)}'), result: (_) {});
    await tester.tap(find.byKey(const ValueKey('mit-pick-profile')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось прочитать профиль'), findsOneWidget);
    expect(find.textContaining('private/path'), findsNothing);
    expect(find.textContaining(testWgKey(1)), findsNothing);
  });

  test('bounded file reader enforces actual bytes and strict UTF8', () async {
    final config = awgTestConfig();
    expect(await readVpnProfileText(Stream.fromIterable([utf8.encode(config)])), config);
    await expectLater(readVpnProfileText(Stream.fromIterable([List.filled(maxVpnProfileBytes, 65), [66]])), throwsFormatException);
    await expectLater(readVpnProfileText(Stream.fromIterable([[0xFF]])), throwsFormatException);
  });
}
