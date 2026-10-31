import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/one_tap/vpn_profile.dart';

import 'fixtures/awg_fixture.dart';

Map<String, dynamic> endpoint(String text) => (jsonDecode(prepareVpnProfile(text).content)['endpoints'] as List).single as Map<String, dynamic>;

void main() {
  for (final version in [1, 2, 3]) {
    test('imports an Amnezia client vpn link and preserves AWG $version options', () {
      final prepared = prepareVpnProfile(amneziaTestLink(amneziaTestContainer(awgTestConfig(version: version))));
      final out = endpoint(amneziaTestLink(amneziaTestContainer(awgTestConfig(version: version))));
      expect(prepared.protocol, MitVpnProtocol.amneziaWg);
      expect(out['type'], 'awg');
      expect(out['private_key'], testWgKey(1));
      expect(out['address'], ['10.8.0.2/32', 'fd42::2/128']);
      final peer = (out['peers'] as List).single as Map;
      expect(peer['preshared_key'], testWgKey(33));
      expect(peer['allowed_ips'], ['0.0.0.0/0', '::/0']);
      expect(peer['persistent_keepalive_interval'], 25);
      expect(out['awg']['h1'], version >= 2 ? '1001-1009' : '1001');
      if (version >= 2) {
        expect(out['awg']['s3'], 6);
        expect(out['awg']['s4'], 8);
        expect(out['awg']['i1'], '<b 0x01020304>');
      }
      if (version >= 3) {
        expect(out['awg']['header_protection_key'], List.filled(64, '1').join());
        expect(out['awg']['rekey_after_time'], '100-120');
        expect(out['awg']['random_trailers'], true);
        expect(out['awg']['disable_cookies'], false);
      }
      expect(prepared.content, isNot(contains('private-display-name')));
      expect(prepared.content, isNot(contains('private-administrative-host')));
      expect(prepared.content, isNot(contains('containers')));
      expect(prepared.toString(), isNot(contains(testWgKey(1))));
      expect(jsonDecode(prepared.content).keys, ['endpoints']);
    });
  }

  test('accepts legacy uncompressed JSON, CRLF, BOM and comments', () {
    final config = '\uFEFF# Name = private-name\r\n${awgTestConfig().replaceAll('\n', '\r\n')}';
    expect(endpoint(config)['tag'], 'Mit-AWG');
    expect(endpoint(amneziaTestLink(amneziaTestContainer(awgTestConfig()), compressed: false))['type'], 'awg');
  });

  test('imports base64 conf and query style awg links with IPv6 endpoint', () {
    final conf = awgTestConfig().replaceFirst('192.0.2.10:51820', '[2001:db8::1]:51820');
    expect(endpoint('awg://${base64Url.encode(utf8.encode(conf))}')['peers'][0]['address'], '2001:db8::1');
    final query = Uri(scheme: 'awg', host: '2001:db8::1', port: 51820, queryParameters: {
      'pk': testWgKey(1), 'publickey': testWgKey(65), 'psk': testWgKey(33),
      'address': '10.8.0.2/32', 'allowedips': '0.0.0.0/0',
      'jc': '4', 'jmin': '40', 'jmax': '70', 's1': '15', 's2': '18',
      'h1': '1001', 'h2': '2001', 'h3': '3001', 'h4': '4001', 'keepalive': '25',
    }).toString();
    expect(endpoint(query)['awg']['s1'], 15);
    expect(endpoint(query)['peers'][0]['address'], '2001:db8::1');
    expect(() => prepareVpnProfile('$query&pk=duplicate'), throwsA(isA<VpnProfileException>()));
    expect(() => prepareVpnProfile('$query&detour=direct'), throwsA(isA<VpnProfileException>()));
  });

  test('still imports VLESS REALITY unchanged', () {
    final pbk = base64Url.encode(List.generate(32, (i) => i + 1)).replaceAll('=', '');
    final link = 'vless://00000000-0000-4000-8000-000000000001@example.com:443?security=reality&sni=example.com&fp=chrome&pbk=$pbk';
    final prepared = prepareVpnProfile(link);
    expect(prepared.protocol, MitVpnProtocol.reality);
    expect(prepared.content, link);
  });

  test('never accepts server administration, subscriptions or ambiguous containers', () {
    final admin = amneziaTestContainer(awgTestConfig())..['password'] = 'private-admin-password';
    expect(() => prepareVpnProfile(amneziaTestLink(admin)), throwsA(isA<VpnProfileException>().having((e) => e.message, 'safe explanation', contains('Поделиться подключением'))));
    final multi = amneziaTestContainer(awgTestConfig());
    (multi['containers'] as List).add((multi['containers'] as List).first);
    expect(() => prepareVpnProfile(amneziaTestLink(multi)), throwsA(isA<VpnProfileException>()));
    for (final input in ['https://example.com/profile', '{"endpoints":[]}', 'vpn://bad', 'vpn://${base64Url.encode(utf8.encode('{"api_key":"synthetic"}'))}']) {
      expect(() => prepareVpnProfile(input), throwsA(isA<VpnProfileException>()));
    }
  });

  test('bounds declared and actual decompression size and checks the Qt length', () {
    final prefix = ByteData(4)..setUint32(0, 32);
    final bomb = [...prefix.buffer.asUint8List(), ...zlib.encode(List.filled(maxVpnProfileBytes * 4, 65))];
    expect(() => prepareVpnProfile('vpn://${base64Url.encode(bomb)}'), throwsA(isA<VpnProfileException>()));
    final tooLarge = ByteData(4)..setUint32(0, maxVpnProfileBytes + 1);
    expect(() => prepareVpnProfile('vpn://${base64Url.encode([...tooLarge.buffer.asUint8List(), ...zlib.encode([1])])}'), throwsA(isA<VpnProfileException>()));
    final mismatch = [...prefix.buffer.asUint8List(), ...zlib.encode(utf8.encode('{}'))];
    expect(() => prepareVpnProfile('vpn://${base64Url.encode(mismatch)}'), throwsA(isA<VpnProfileException>()));
  });

  final invalid = <String, String Function(String)>{
    'missing private key': (s) => s.replaceFirst('PrivateKey = ${testWgKey(1)}', ''),
    'invalid public key': (s) => s.replaceFirst(testWgKey(65), 'invalid-public-key'),
    'duplicate private key': (s) => s.replaceFirst('MTU = 1280', 'PrivateKey = ${testWgKey(1)}'),
    'unknown obfuscation': (s) => s.replaceFirst('MTU = 1280', 'FutureObfuscation = 1'),
    'shell command': (s) => s.replaceFirst('MTU = 1280', 'PostUp = echo private-command'),
    'second peer': (s) => '$s\n[Peer]\nPublicKey = ${testWgKey(65)}',
    'second profile': (s) => '$s\n$s',
    'bad endpoint port': (s) => s.replaceFirst(':51820', ':65536'),
    'bad address': (s) => s.replaceFirst('10.8.0.2/32', '10.8.0.2/33'),
    'bad allowed IP': (s) => s.replaceFirst('0.0.0.0/0', 'example.com'),
    'malformed numeric': (s) => s.replaceFirst('Jc = 4', 'Jc = invalid'),
    'unbounded junk': (s) => s.replaceFirst('Jc = 4', 'Jc = 99999999'),
    'reversed junk range': (s) => s.replaceFirst('Jmax = 70', 'Jmax = 20'),
    'bad header range': (s) => s.replaceFirst('1001-1009', '1009-1001'),
    'bad header key': (s) => s.replaceFirst(List.filled(64, '1').join(), 'bad-key'),
    'bad boolean': (s) => s.replaceFirst('RandomTrailers = 1', 'RandomTrailers = invalid'),
    'oversized input': (s) => 'x' * (maxVpnProfileBytes + 1),
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key} without showing credential or source', () {
      try {
        prepareVpnProfile(entry.value(awgTestConfig(version: 3)));
        fail('accepted invalid profile');
      } on VpnProfileException catch (error) {
        expect(error.source, isNull);
        expect(error.toString(), isNot(contains(testWgKey(1))));
        expect(error.toString(), isNot(contains('192.0.2.10')));
        expect(error.toString(), isNot(contains('private-command')));
      }
    });
  }
}
