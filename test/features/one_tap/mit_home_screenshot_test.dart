import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/one_tap/mit_brand.dart';
import 'package:hiddify/features/one_tap/mit_brand_pages.dart';
import 'package:hiddify/features/one_tap/one_tap_home_page.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

ProfileEntity get _profile => ProfileEntity.local(id: 'synthetic', active: true, name: 'VPN', lastUpdate: DateTime(2026));
class _Profile extends ActiveProfile {
  @override
  Stream<ProfileEntity?> build() => Stream.value(_profile);
}
class _Profiles extends ProfilesNotifier {
  @override
  Stream<List<ProfileEntity>> build() => Stream.value([_profile]);
}
class _Locale extends LocalePreferences {
  @override
  AppLocale build() => AppLocale.ru;
}
class _Analytics extends AnalyticsController {
  @override
  Future<bool> build() async => false;
}
class _Status extends ConnectionNotifier {
  _Status(this.current);
  final ConnectionStatus current;
  @override
  Stream<ConnectionStatus> build() => Stream.value(current);
}

void main() {
  final cases = <String, (Widget, ConnectionStatus)>{
    'disconnected': (const OneTapHomePage(), const Disconnected()),
    'connected': (const OneTapHomePage(), const Connected()),
    'error': (const OneTapHomePage(), const Disconnected(ConnectionFailure.invalidConfig('synthetic-error'))),
    'intro': (const MitIntroPage(), const Disconnected()),
    'settings': (const MitSettingsPage(), const Disconnected()),
    'about': (const MitAboutPage(), const Disconnected()),
    'profiles': (const MitPage(title: 'Профили', child: MitProfilesSheet()), const Disconnected()),
  };
  for (final entry in cases.entries) {
    testWidgets('render and export ${entry.key} screen', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(overrides: [
        activeProfileProvider.overrideWith(_Profile.new),
        profilesNotifierProvider.overrideWith(_Profiles.new),
        connectionNotifierProvider.overrideWith(() => _Status(entry.value.$2)),
        localePreferencesProvider.overrideWith(_Locale.new),
        translationsProvider.overrideWith((ref) => AppLocale.ru.build()),
        analyticsControllerProvider.overrideWith(_Analytics.new),
      ]);
      addTearDown(container.dispose);
      await container.read(translationsProvider.future);
      await container.read(analyticsControllerProvider.future);
      final key = GlobalKey();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(key: key, child: MaterialApp(home: entry.value.$1)),
      ));
      await tester.runAsync(() async {
        final context = key.currentContext!;
        await precacheImage(const AssetImage('assets/images/mit_vpn_background.png'), context);
        await precacheImage(const AssetImage(MitBrand.icon), context);
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(bytes, isNotNull);
          final directory = Directory('build/ui-preview')..createSync(recursive: true);
          await File('${directory.path}/mits-vpn-${entry.key}.png').writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    });
  }
}
