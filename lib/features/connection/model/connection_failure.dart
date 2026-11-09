import 'package:flutter/services.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/features/settings/model/config_option_failure.dart';
import 'package:hiddify/hiddifycore/core_interface/desktop_vpn_exception.dart';

part 'connection_failure.freezed.dart';

@freezed
sealed class ConnectionFailure with _$ConnectionFailure, Failure {
  const ConnectionFailure._();

  @With<UnexpectedFailure>()
  const factory ConnectionFailure.unexpected([Object? error, StackTrace? stackTrace]) = UnexpectedConnectionFailure;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.missingVpnPermission([String? message]) = MissingVpnPermission;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.missingNotificationPermission([String? message]) = MissingNotificationPermission;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.missingPrivilege() = MissingPrivilege;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.tunAddressInUse() = TunAddressInUse;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.invalidConfigOption([String? message, ConfigOptionFailure? configOptionFailure]) =
      InvalidConfigOption;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.invalidConfig([String? message]) = InvalidConfig;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.backgroundCoreNotAvailable([String? message]) = BackgroundCoreNotAvailable;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.missiingWarpLicense() = MissingWarpLicense;

  @With<ExpectedMeasuredFailure>()
  const factory ConnectionFailure.missingPsiphonLicense() = MissingPsiphonLicense;

  factory ConnectionFailure.fromError(Object error, [StackTrace? stackTrace]) => switch (error) {
    ConnectionFailure() => error,
    PlatformException(code: 'MACOS_VPN_APPROVAL_REQUIRED', :final message) => ConnectionFailure.missingVpnPermission(
      message,
    ),
    PlatformException(code: 'MACOS_VPN', message: final message?) => ConnectionFailure.unexpected(message, stackTrace),
    _ => ConnectionFailure.unexpected(error, stackTrace),
  };

  /// One-tap messages contain fixed text only; native errors can contain credentials.
  ({String type, String? message}) presentOneTap({required bool windows}) {
    final message = switch (this) {
      UnexpectedConnectionFailure(error: final DesktopVpnException error) => error.toString(),
      MissingPrivilege() ||
      MissingVpnPermission() when windows => const DesktopVpnException(DesktopVpnError.permission).toString(),
      TunAddressInUse() when windows =>
        'Адрес VPN-туннеля занят. Отключите другой VPN и повторите подключение. Код: WIN-VPN-06.',
      InvalidConfig() || InvalidConfigOption() => 'Не удалось применить профиль VPN. Проверьте конфигурацию профиля.',
      BackgroundCoreNotAvailable() when windows => const DesktopVpnException(
        DesktopVpnError.controlConnection,
      ).toString(),
      _ when windows => 'Не удалось подключить VPN в Windows. Проверьте сеть и профиль. Код: WIN-VPN-00.',
      _ => 'Проверьте сеть, профиль и разрешение на подключение VPN.',
    };
    return (type: 'Ошибка VPN', message: message);
  }

  @override
  ({String type, String? message}) present(TranslationsEn t) {
    return switch (this) {
      UnexpectedConnectionFailure(:final error) when error != null => (
        type: t.errors.connectivity.unexpected,
        message: "$error",
      ),
      UnexpectedConnectionFailure() => (type: t.errors.connectivity.unexpected, message: null),
      MissingVpnPermission(:final message) => (type: t.errors.connectivity.missingVpnPermission, message: message),
      MissingNotificationPermission(:final message) => (
        type: t.errors.connectivity.missingNotificationPermission,
        message: message,
      ),
      MissingPrivilege() => (type: t.errors.singbox.missingPrivilege, message: t.errors.singbox.missingPrivilegeMsg),
      TunAddressInUse() => (type: t.errors.singbox.tunAddressInUse, message: t.errors.singbox.tunAddressInUseMsg),
      InvalidConfigOption(:final message, :final configOptionFailure) =>
        configOptionFailure?.present(t) ?? (type: t.errors.singbox.invalidConfigOptions, message: message),
      InvalidConfig(:final message) => (type: t.errors.singbox.invalidConfig, message: message),
      BackgroundCoreNotAvailable(:final message) => (type: t.errors.connectivity.core, message: message),
      MissingWarpLicense() => (type: t.errors.warp.missingLicense, message: t.errors.warp.missingLicenseMsg),
      MissingPsiphonLicense() => (type: t.errors.psiphon.missingLicense, message: t.errors.psiphon.missingLicenseMsg),
    };
  }
}
