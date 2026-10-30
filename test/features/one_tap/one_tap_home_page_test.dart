import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/one_tap/one_tap_home_page.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _NoProfile extends ActiveProfile {
  @override
  Stream<ProfileEntity?> build() => Stream.value(null);
}

class _Disconnected extends ConnectionNotifier {
  @override
  Stream<ConnectionStatus> build() => Stream.value(const Disconnected());
}

class _Connecting extends ConnectionNotifier {
  @override
  Stream<ConnectionStatus> build() => Stream.value(const Connecting());
}

void main() {
  testWidgets('empty state imports explicitly and rejects subscription URLs before repository access', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeProfileProvider.overrideWith(_NoProfile.new),
        connectionNotifierProvider.overrideWith(_Disconnected.new),
      ],
      child: const MaterialApp(home: OneTapHomePage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Добавьте профиль для подключения'), findsOneWidget);
    await tester.tap(find.byWidgetPredicate((widget) => widget is FilledButton));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    await tester.enterText(find.byType(TextField), 'https://example.com/private-subscription');
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось добавить профиль VLESS + REALITY. Проверьте ссылку.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('profile changes are disabled during a connection attempt', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeProfileProvider.overrideWith(_NoProfile.new),
        connectionNotifierProvider.overrideWith(_Connecting.new),
      ],
      child: const MaterialApp(home: OneTapHomePage()),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byWidgetPredicate((widget) => widget is FilledButton)).onPressed, isNull);
  });
}
