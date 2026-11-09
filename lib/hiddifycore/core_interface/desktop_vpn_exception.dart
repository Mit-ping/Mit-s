/// Fixed diagnostic codes: never include a profile, key or native error text in UI.
enum DesktopVpnError { permission, serviceInstall, tunnelStart, controlAccess, controlConnection }

class DesktopVpnException implements Exception {
  const DesktopVpnException(this.code);
  final DesktopVpnError code;

  String get diagnosticCode => switch (code) {
    DesktopVpnError.permission => 'WIN-VPN-01',
    DesktopVpnError.serviceInstall => 'WIN-VPN-02',
    DesktopVpnError.tunnelStart => 'WIN-VPN-03',
    DesktopVpnError.controlAccess => 'WIN-VPN-04',
    DesktopVpnError.controlConnection => 'WIN-VPN-05',
  };

  String get userMessage => switch (code) {
    DesktopVpnError.permission =>
      'Windows не предоставила права администратора для службы VPN. Повторите подключение и подтвердите запрос.',
    DesktopVpnError.serviceInstall =>
      'Не удалось установить или запустить службу VPN Windows. Повторите установку приложения.',
    DesktopVpnError.tunnelStart =>
      'Служба Windows запущена, но VPN-туннель не удалось создать. Проверьте профиль и отключите другой VPN.',
    DesktopVpnError.controlAccess =>
      'Приложение не получило доступ к службе VPN Windows. Повторите установку под своей учётной записью.',
    DesktopVpnError.controlConnection => 'Не удалось связаться со службой VPN Windows. Повторите подключение.',
  };

  @override
  String toString() => '$diagnosticCode: $userMessage';
}
