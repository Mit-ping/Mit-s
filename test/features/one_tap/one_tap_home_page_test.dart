import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/one_tap/one_tap_home_page.dart';
import 'package:hiddify/features/one_tap/mit_connection_controls.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Active extends ActiveProfile {
  _Active(this.profile);
  final ProfileEntity? profile;
  @override
  Stream<ProfileEntity?> build() => Stream.value(profile);
}

class _Core extends ConnectionNotifier {
  _Core(this.current, this.onToggle);
  final ConnectionStatus current;
  final VoidCallback onToggle;
  @override
  Stream<ConnectionStatus> build() => Stream.value(current);
  @override
  Future<void> toggleConnection() async => onToggle();
  void emit(ConnectionStatus next) => state = AsyncData(next);
}

class _Sheets extends BottomSheetsNotifier {
  _Sheets(this.onOpen);
  final VoidCallback onOpen;
  @override
  void build() {}
  @override
  Future<void> showProfilesOverview() async => onOpen();
}

class _Dialogs extends DialogNotifier {
  @override
  void build() {}
  @override
  Future<bool> showExperimentalFeatureNotice() async => true;
}

void main() {
  final profile = ProfileEntity.local(id: 'synthetic', active: true, name: 'VPN', lastUpdate: DateTime(2026));
  Future<void> open(WidgetTester tester, {ProfileEntity? selected, ConnectionStatus status = const Disconnected(), VoidCallback? onToggle}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeProfileProvider.overrideWith(() => _Active(selected)),
        connectionNotifierProvider.overrideWith(() => _Core(status, onToggle ?? () {})),
        dialogNotifierProvider.overrideWith(_Dialogs.new),
      ],
      child: const MaterialApp(home: OneTapHomePage()),
    ));
    await tester.pumpAndSettle();
  }

  Color ringColor(WidgetTester tester) {
    final ring = tester.widget<AnimatedContainer>(find.descendant(
      of: find.byType(MitConnectionControls), matching: find.byType(AnimatedContainer),
    ));
    return ((ring.decoration! as BoxDecoration).border! as Border).top.color;
  }

  testWidgets('empty state imports explicitly and rejects subscription URLs before repository access', (tester) async {
    await open(tester);
    expect(find.text('Добавьте профиль для подключения'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('add-reality-profile')));
    await tester.tap(find.byKey(const ValueKey('add-reality-profile')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    expect(tester.widget<TextField>(find.byType(TextField)).enableIMEPersonalizedLearning, isFalse);
    await tester.enterText(find.byType(TextField), 'https://example.com/private-subscription');
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось добавить профиль VLESS + REALITY. Проверьте ссылку.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('neon power button starts real notifier action', (tester) async {
    var calls = 0;
    await open(tester, selected: profile, onToggle: () => calls++);
    expect(tester.widget<Icon>(find.byIcon(Icons.power_settings_new_rounded)).color, mitIdle);
    expect(ringColor(tester), mitIdle);
    await tester.tap(find.byKey(const ValueKey('mit-power-button')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Готов к подключению'), findsOneWidget);
    // The UI does not simulate a successful connection on tap.
    expect(find.text('VPN подключён'), findsNothing);
  });

  for (final state in <ConnectionStatus>[
    const Connecting(), const Connected(), const Waiting(), const NoAvailableProxies(), const HotReloading(),
  ]) {
    testWidgets('can stop ${state.runtimeType} without any active profile', (tester) async {
      var calls = 0;
      await open(tester, status: state, onToggle: () => calls++);
      final color = tester.widget<Icon>(find.byIcon(Icons.power_settings_new_rounded)).color;
      expect(color, state is Connected ? mitGreen : isNot(mitGreen));
      expect(ringColor(tester), state is Connected ? mitGreen : isNot(mitGreen));
      await tester.tap(find.byKey(const ValueKey('mit-power-button')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      final add = tester.widget<OutlinedButton>(find.byKey(const ValueKey('add-reality-profile')));
      expect(add.onPressed, isNull);
      if (state is Waiting || state is NoAvailableProxies) {
        expect(find.text('VPN подключён'), findsNothing);
      }
    });
  }

  testWidgets('disconnecting disables the power button and profile changes', (tester) async {
    var calls = 0;
    await open(tester, selected: profile, status: const Disconnecting(), onToggle: () => calls++);
    final button = tester.widget<InkWell>(find.byKey(const ValueKey('mit-power-button')));
    expect(button.onTap, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('add-reality-profile'))).onPressed, isNull);
    expect(calls, 0);
  });

  testWidgets('an already-open menu rechecks native status before profile selection', (tester) async {
    var opened = 0;
    final core = _Core(const Disconnected(), () {});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeProfileProvider.overrideWith(() => _Active(profile)),
        connectionNotifierProvider.overrideWith(() => core),
        bottomSheetsNotifierProvider.overrideWith(() => _Sheets(() => opened++)),
      ],
      child: const MaterialApp(home: OneTapHomePage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Меню'));
    await tester.pumpAndSettle();
    core.emit(const Connected());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать профиль'));
    await tester.pumpAndSettle();
    expect(opened, 0);
  });

  testWidgets('error screen hides native error contents', (tester) async {
    await open(tester, selected: profile, status: const Disconnected(ConnectionFailure.invalidConfig('private-profile-content')));
    expect(find.text('Не удалось подключиться'), findsOneWidget);
    expect(find.textContaining('private-profile-content'), findsNothing);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('small screens and large text scroll without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester, selected: profile);
    await tester.ensureVisible(find.byKey(const ValueKey('add-reality-profile')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
