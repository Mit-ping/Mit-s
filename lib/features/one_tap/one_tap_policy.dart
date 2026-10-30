import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/utils/platform_utils.dart';

/// Mit’s VPN is the Android default; iOS/Windows keep their existing workflow.
bool get oneTapVpnEnabled =>
    const bool.fromEnvironment('ONE_TAP_VPN', defaultValue: true) && PlatformUtils.isAndroid;

/// Applied after subscription overrides. Never persists over the user's rules.
SingboxConfigOption applyOneTapPolicy(SingboxConfigOption options, {required bool enabled}) {
  if (!enabled) return options;
  final rules = [
    BuiltinRule.bypassLan.rule,
    Rule(name: 'one-tap:ru-domains', outbound: Outbound.direct, domainSuffixes: ['ru', 'su', 'xn--p1ai']),
    BuiltinRule.bypassRegion.rule,
  ];
  for (final (index, rule) in rules.indexed) {
    rule.enabled = true;
    rule.listOrder = index;
  }
  return options.copyWith(
    region: 'ru',
    enableTun: true,
    setSystemProxy: false,
    executeConfigAsIs: false,
    allowConnectionFromLan: false,
    enableClashApi: false,
    routeRule: RouteRule(rules: rules).toProto3Json()! as Map<String, dynamic>,
  );
}
