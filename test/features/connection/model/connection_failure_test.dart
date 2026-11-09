import 'package:flutter/services.dart';
import 'package:hiddify/hiddifycore/core_interface/desktop_vpn_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/gen/translations.g.dart';

void main() {
  test('Windows one-tap diagnostics identify the failed service stage', () {
    for (final code in DesktopVpnError.values) {
      final error = DesktopVpnException(code);
      final failure = ConnectionFailure.fromError(error);
      final message = failure.presentOneTap(windows: true).message!;
      expect(message, contains(error.diagnosticCode));
      expect(message, isNot(contains('Android')));
    }
  });

  test('one-tap errors never expose a native error containing a profile key', () {
    for (final failure in [
      const ConnectionFailure.unexpected('vless://secret@example.com'),
      const ConnectionFailure.invalidConfig('private_key=secret'),
      const ConnectionFailure.missingVpnPermission('private_key=secret'),
      const ConnectionFailure.backgroundCoreNotAvailable('password=secret'),
    ]) {
      for (final windows in [true, false]) {
        final message = failure.presentOneTap(windows: windows).message!;
        expect(message, isNot(contains('secret')));
        expect(message, isNot(contains('Android')));
      }
    }
  });

  test('macOS extension approval is an expected permission prompt with readable instructions', () {
    const message = 'Allow Hiddify in System Settings, then connect again.';
    final failure = ConnectionFailure.fromError(
      PlatformException(code: 'MACOS_VPN_APPROVAL_REQUIRED', message: message),
    );

    expect(failure, isA<ExpectedMeasuredFailure>());
    expect(failure, isA<MissingVpnPermission>());
    expect(failure.present(TranslationsEn()).type, 'Missing VPN permission');
    expect(failure.present(TranslationsEn()).message, message);
  });

  test('unclassified native failures remain errors without the platform wrapper', () {
    final failure = ConnectionFailure.fromError(
      PlatformException(code: 'MACOS_VPN', message: 'The packet tunnel failed to start.'),
    );

    expect(failure, isA<UnexpectedConnectionFailure>());
    expect(failure.present(TranslationsEn()).message, 'The packet tunnel failed to start.');
  });
}
