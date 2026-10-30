import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/one_tap/one_tap_policy.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Rules extends RulesNotifier {
  @override
  List<Rule> build() => [Rule(name: 'custom-direct', enabled: true, outbound: Outbound.direct)];
}

void main() {
  late ProviderContainer container;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'region': 'cn'});
    container = ProviderContainer(overrides: [rulesNotifierProvider.overrideWith(_Rules.new)]);
    await container.read(sharedPreferencesProvider.future);
  });
  tearDown(() => container.dispose());

  test('disabled policy preserves desktop/iOS options and saved rules', () {
    final original = container.read(ConfigOptions.singboxConfigOptions);
    expect(identical(applyOneTapPolicy(original, enabled: false), original), isTrue);
  });

  test('pilot forces VPN and Russian rules without modifying stored settings', () {
    final original = container.read(ConfigOptions.singboxConfigOptions);
    final policy = applyOneTapPolicy(original, enabled: true);
    expect(policy.region, 'ru');
    expect(policy.enableTun, isTrue);
    expect(policy.executeConfigAsIs, isFalse);
    expect(policy.allowConnectionFromLan, isFalse);
    expect(policy.enableClashApi, isFalse);
    final rules = RouteRule()..mergeFromProto3Json(policy.routeRule);
    expect(rules.rules.map((r) => r.listOrder), [0, 1, 2]);
    expect(rules.rules.every((r) => r.enabled && r.outbound == Outbound.direct), isTrue);
    expect(rules.rules[1].domainSuffixes, ['ru', 'su', 'xn--p1ai']);
    expect(rules.rules[2].ruleSets, everyElement(contains('{region}')));
    expect(rules.rules[2].ruleSets.length, 2);
    expect(original.region, 'cn');
    expect(container.read(rulesNotifierProvider).single.name, 'custom-direct');
    expect(applyOneTapPolicy(policy, enabled: true).toJson(), policy.toJson());
  });
}
