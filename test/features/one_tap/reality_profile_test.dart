import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/one_tap/reality_profile.dart';

void main() {
  // Synthetic test credentials; no live endpoint or subscription.
  final key = base64Url.encode(List.generate(32, (i) => i + 1)).replaceAll('=', '');
  final link = 'vless://00000000-0000-4000-8000-000000000001@example.com:443'
      '?security=reality&type=tcp&encryption=none&flow=xtls-rprx-vision'
      '&sni=example.com&fp=chrome&pbk=$key&sid=abcd#Test';

  test('accepts a single REALITY/TCP profile, trimming clipboard whitespace', () {
    expect(validateRealityProfile('  $link\n'), link);
  });

  test('supports IPv6 endpoints and optional empty short ID', () {
    expect(validateRealityProfile(link.replaceFirst('example.com:443', '[2001:db8::1]:443').replaceFirst('sid=abcd', 'sid=')), isNotEmpty);
  });

  final invalid = <String, String>{
    'unencrypted': link.replaceFirst('security=reality', 'security=none'),
    'TLS without REALITY': link.replaceFirst('security=reality', 'security=tls'),
    'unsupported transport': link.replaceFirst('type=tcp', 'type=ws'),
    'bad UUID': link.replaceFirst('00000000-0000-4000-8000-000000000001', 'password'),
    'missing port': link.replaceFirst(':443', ''),
    'invalid port': link.replaceFirst(':443', ':65536'),
    'missing SNI': link.replaceFirst('sni=example.com', 'sni='),
    'malformed SNI': link.replaceFirst('sni=example.com', 'sni=-example..com'),
    'invalid key': link.replaceFirst('pbk=$key', 'pbk=bad'),
    'invalid short ID': link.replaceFirst('sid=abcd', 'sid=abc'),
    'insecure override': '$link&allowInsecure=1'.replaceFirst('#Test', ''),
    'duplicate security': link.replaceFirst('security=reality', 'security=reality&security=none'),
    'multiple profiles': '$link\n$link',
    'subscription URL': 'https://example.com/private-subscription',
    'JSON': '{"outbounds":[]}',
    'oversized input': 'vless://${'a' * 8193}',
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key} without exposing the input', () {
      try {
        validateRealityProfile(entry.value);
        fail('accepted invalid input');
      } on FormatException catch (error) {
        expect(error.source, isNull);
        expect(error.toString(), isNot(contains('example.com')));
        expect(error.toString(), isNot(contains(key)));
        expect(error.toString(), isNot(contains('00000000')));
      }
    });
  }
}
