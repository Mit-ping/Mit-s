import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/one_tap/mit_brand.dart';
import 'package:hiddify/features/one_tap/mit_brand_pages.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _LegalBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'assets/legal/NOTICE.txt') return ByteData.sublistView(File(key).readAsBytesSync());
    return rootBundle.load(key);
  }
}

class _Analytics extends AnalyticsController {
  @override
  Future<bool> build() async => false;
}

class _Locale extends LocalePreferences {
  @override
  AppLocale build() => AppLocale.ru;
}

class _Core extends ConnectionNotifier {
  _Core(this.current);
  final ConnectionStatus current;
  @override
  Stream<ConnectionStatus> build() => Stream.value(current);
  void emit(ConnectionStatus next) => state = AsyncData(next);
}

class _Profiles extends ProfilesNotifier {
  int selections = 0;
  int deletions = 0;
  @override
  Stream<List<ProfileEntity>> build() => Stream.value([
    ProfileEntity.local(id: 'synthetic', active: true, name: 'private-profile-name', lastUpdate: DateTime(2026)),
  ]);
  @override
  Future<Unit> selectActiveProfile(String id) async { selections++; return unit; }
  @override
  Future<void> deleteProfile(ProfileEntity profile) async { deletions++; }
}

void main() {
  for (final page in <String, Widget>{
    'intro': const MitIntroPage(), 'about': const MitAboutPage(), 'settings': const MitSettingsPage(),
  }.entries) {
    testWidgets('${page.key} shows Mit identity without upstream product promotion', (tester) async {
      final container = ProviderContainer(overrides: [
        localePreferencesProvider.overrideWith(_Locale.new),
        analyticsControllerProvider.overrideWith(_Analytics.new),
        translationsProvider.overrideWith((ref) => AppLocale.ru.build()),
      ]);
      addTearDown(container.dispose);
      await tester.runAsync(() async {
        await container.read(translationsProvider.future);
        await container.read(analyticsControllerProvider.future);
      });
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: page.value)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hiddify'), findsNothing);
      expect(find.byType(MitLogo), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('required upstream license is retained in the dedicated legal page', (tester) async {
    await tester.pumpWidget(DefaultAssetBundle(bundle: _LegalBundle(), child: const MaterialApp(home: MitLegalPage())));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data, contains('https://github.com/hiddify/hiddify-app'));
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data, contains('Source Code Availability'));
  });

  Future<void> openProfiles(WidgetTester tester, _Core core, _Profiles profiles) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        connectionNotifierProvider.overrideWith(() => core),
        profilesNotifierProvider.overrideWith(() => profiles),
      ],
      child: MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const MitProfilesSheet()),
        child: const Text('Открыть'),
      )))),
    ));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
  }

  testWidgets('profile selection uses the existing repository notifier without exposing profile content', (tester) async {
    final profiles = _Profiles();
    await openProfiles(tester, _Core(const Disconnected()), profiles);
    expect(find.textContaining('private-profile-name'), findsNothing);
    await tester.tap(find.text('Профиль 1'));
    await tester.pumpAndSettle();
    expect(profiles.selections, 1);
  });

  testWidgets('profile deletion requires confirmation and rechecks live VPN state', (tester) async {
    final core = _Core(const Disconnected());
    final profiles = _Profiles();
    await openProfiles(tester, core, profiles);
    await tester.tap(find.byTooltip('Удалить профиль'));
    await tester.pumpAndSettle();
    expect(profiles.deletions, 0);
    core.emit(const Connected());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(profiles.deletions, 0);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.delete_outline)).onPressed, isNull);
  });
}
