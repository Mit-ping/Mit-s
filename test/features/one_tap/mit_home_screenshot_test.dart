import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/one_tap/one_tap_home_page.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Profile extends ActiveProfile {
  @override
  Stream<ProfileEntity?> build() => Stream.value(
    ProfileEntity.local(id: 'synthetic', active: true, name: 'VPN', lastUpdate: DateTime(2026)),
  );
}

class _Status extends ConnectionNotifier {
  _Status(this.current);
  final ConnectionStatus current;
  @override
  Stream<ConnectionStatus> build() => Stream.value(current);
}

void main() {
  final cases = <String, ConnectionStatus>{
    'disconnected': const Disconnected(),
    'connected': const Connected(),
    'error': const Disconnected(ConnectionFailure.invalidConfig('synthetic-error')),
  };
  for (final entry in cases.entries) {
    testWidgets('render and export ${entry.key} screen', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          activeProfileProvider.overrideWith(_Profile.new),
          connectionNotifierProvider.overrideWith(() => _Status(entry.value)),
        ],
        child: RepaintBoundary(key: key, child: const MaterialApp(home: OneTapHomePage())),
      ));
      await tester.runAsync(() => precacheImage(
        const AssetImage('assets/images/mit_vpn_background.png'),
        tester.element(find.byType(OneTapHomePage)),
      ));
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
