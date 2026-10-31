import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hiddify/features/one_tap/reality_profile.dart';

const maxVpnProfileBytes = 64 * 1024;

enum MitVpnProtocol {
  reality('VLESS + REALITY', 'VPN'),
  amneziaWg('AmneziaWG', 'AmneziaWG');

  const MitVpnProtocol(this.label, this.profileName);
  final String label;
  final String profileName;
}

String mitProfileProtocolLabel(String? storedName) => storedName == MitVpnProtocol.amneziaWg.profileName
    ? MitVpnProtocol.amneziaWg.label
    : storedName == MitVpnProtocol.reality.profileName ? MitVpnProtocol.reality.label : 'VPN';

/// Only validated client credentials reach the repository. Input containers,
/// display names, server administration data and routing overrides never do.
class PreparedVpnProfile {
  const PreparedVpnProfile(this.protocol, this.content);
  final MitVpnProtocol protocol;
  final String content;

  @override
  String toString() => 'PreparedVpnProfile(${protocol.label})';
}

class VpnProfileException extends FormatException {
  const VpnProfileException(super.message);
}

const _invalid = VpnProfileException('Нужна ссылка VLESS + REALITY или клиентский профиль AmneziaWG.');
const _admin = VpnProfileException('Используйте ключ «Поделиться подключением» Amnezia, а не полный доступ к серверу.');
const _remote = VpnProfileException('Нужен готовый клиентский ключ AWG или файл .conf. Ключи доступа к сервису Amnezia пока не поддерживаются.');

PreparedVpnProfile prepareVpnProfile(String input) {
  try {
    if (input.length > maxVpnProfileBytes || utf8.encode(input).length > maxVpnProfileBytes) throw _invalid;
    var text = input.trim().replaceFirst(RegExp(r'^\uFEFF'), '').trim();
    if (text.startsWith('vless://')) {
      return PreparedVpnProfile(MitVpnProtocol.reality, validateRealityProfile(text));
    }
    if (text.startsWith('vpn://')) {
      text = _amneziaClientConfig(text.substring(6));
    } else if (text.startsWith('awg://')) {
      final payload = text.substring(6);
      if (RegExp(r'^[A-Za-z0-9+/_=-]+$').hasMatch(payload)) {
        text = utf8.decode(_decodeBase64(payload));
      } else {
        text = _awgLinkConfig(text);
      }
    }
    final endpoint = _awgEndpoint(text);
    return PreparedVpnProfile(MitVpnProtocol.amneziaWg, jsonEncode({'endpoints': [endpoint]}));
  } on FormatException catch (e) {
    if (identical(e, _admin) || identical(e, _remote)) rethrow;
    throw _invalid;
  } catch (_) {
    throw _invalid;
  }
}

List<int> _decodeBase64(String text) {
  if (text.length > maxVpnProfileBytes || !RegExp(r'^[A-Za-z0-9+/_-]+={0,2}$').hasMatch(text)) throw _invalid;
  final decoded = base64.decode(base64.normalize(text));
  if (decoded.length > maxVpnProfileBytes) throw _invalid;
  return decoded;
}

String _amneziaClientConfig(String payload) {
  final packed = _decodeBase64(payload);
  List<int> bytes;
  if (packed.isNotEmpty && packed.first == 0x7B) {
    // Older Amnezia exports may contain uncompressed JSON.
    bytes = packed;
  } else {
    if (packed.length < 6) throw _invalid;
    final expected = ByteData.sublistView(Uint8List.fromList(packed), 0, 4).getUint32(0);
    if (expected == 0 || expected > maxVpnProfileBytes) throw _invalid;
    final output = BytesBuilder(copy: false);
    // Bound actual inflated output as well as Qt's declared size. The sink
    // below checks every output chunk, before accumulating it in memory.
    final bounded = ZLibDecoder().startChunkedConversion(_BoundedBytes(output, expected));
    for (var offset = 4; offset < packed.length; offset += 128) {
      final end = offset + 128 < packed.length ? offset + 128 : packed.length;
      bounded.add(packed.sublist(offset, end));
    }
    bounded.close();
    bytes = output.takeBytes();
    if (bytes.length != expected) throw _invalid;
  }
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, dynamic>) throw _invalid;
  for (final key in ['userName', 'password']) {
    if (decoded[key] != null && decoded[key] != '') throw _admin;
  }
  if (decoded.containsKey('api_key') || decoded.containsKey('auth_data')) throw _remote;
  final containers = decoded['containers'];
  if (containers is! List || containers.length != 1) throw _invalid;
  final container = containers.single;
  if (container is! Map || container['container'] is! String ||
      !RegExp(r'^amnezia-awg(?:[-_]?\w+)?$').hasMatch(container['container'] as String)) throw _invalid;
  final awg = container['awg'];
  if (awg is! Map) throw _invalid;
  final last = awg['last_config'];
  final client = last is String ? jsonDecode(last) : last;
  if (client is! Map || client['config'] is! String) throw _invalid;
  return client['config'] as String;
}

class _BoundedBytes extends ByteConversionSinkBase {
  _BoundedBytes(this.output, this.maximum);
  final BytesBuilder output;
  final int maximum;

  @override
  void add(List<int> chunk) {
    if (chunk.length > maximum - output.length) throw _invalid;
    output.add(chunk);
  }

  @override
  void close() {}
}

const _awgFields = {
  'Jc': 'jc', 'Jmin': 'jmin', 'Jmax': 'jmax',
  'S1': 's1', 'S2': 's2', 'S3': 's3', 'S4': 's4',
  'H1': 'h1', 'H2': 'h2', 'H3': 'h3', 'H4': 'h4',
  'I1': 'i1', 'I2': 'i2', 'I3': 'i3', 'I4': 'i4', 'I5': 'i5',
  'HeaderProtectionKey': 'header_protection_key',
  'ContentPaddingAddition': 'content_padding_addition',
  'RekeyAfterTime': 'rekey_after_time', 'RekeyTimeout': 'rekey_timeout',
  'RejectAfterTime': 'reject_after_time', 'KeepaliveTimeout': 'keepalive_timeout',
  'MaxHandshakeAttempts': 'max_handshake_attempts',
  'RandomTrailers': 'random_trailers', 'DisableCookies': 'disable_cookies',
};

Map<String, dynamic> _awgEndpoint(String text) {
  final sections = <String, Map<String, String>>{};
  Map<String, String>? current;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
    if (line == '[Interface]' || line == '[Peer]') {
      if (sections.containsKey(line) || (line == '[Peer]' && !sections.containsKey('[Interface]'))) throw _invalid;
      current = sections[line] = {};
      continue;
    }
    final split = line.indexOf('=');
    if (current == null || split < 1) throw _invalid;
    final key = line.substring(0, split).trim();
    // Comments do not become part of keys or packet templates.
    final value = line.substring(split + 1).split(RegExp(r'\s[#;]')).first.trim();
    if (value.isEmpty || current.containsKey(key) || RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) throw _invalid;
    current[key] = value;
  }
  final local = sections['[Interface]'];
  final peer = sections['[Peer]'];
  if (sections.length != 2 || local == null || peer == null) throw _invalid;
  final interfaceFields = {'PrivateKey', 'Address', 'DNS', 'MTU', 'ListenPort', ..._awgFields.keys};
  const peerFields = {'PublicKey', 'PresharedKey', 'AllowedIPs', 'Endpoint', 'PersistentKeepalive'};
  if (local.keys.any((k) => !interfaceFields.contains(k)) || peer.keys.any((k) => !peerFields.contains(k))) throw _invalid;
  final server = Uri.parse('udp://${peer['Endpoint'] ?? ''}');
  final host = _uriHost(server);
  if (server.host.isEmpty || !server.hasPort || server.userInfo.isNotEmpty || server.path.isNotEmpty ||
      server.hasQuery || server.hasFragment || !_validHost(host)) throw _invalid;
  final port = _number('${server.port}', 1, 65535);
  if (local['DNS'] case final dns?) {
    if (dns.split(',').any((s) => InternetAddress.tryParse(s.trim()) == null || s.contains('%'))) throw _invalid;
  }
  final awg = <String, dynamic>{};
  for (final entry in _awgFields.entries) {
    final value = local[entry.key];
    if (value == null) continue;
    if (entry.key.startsWith('I') && entry.key.length == 2) {
      _validatePacketTemplate(value);
      awg[entry.value] = value;
    } else if (entry.key == 'HeaderProtectionKey') {
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) throw _invalid;
      awg[entry.value] = value;
    } else if (entry.key == 'RandomTrailers' || entry.key == 'DisableCookies') {
      if (!{'true', 'false', '0', '1'}.contains(value.toLowerCase())) throw _invalid;
      awg[entry.value] = value == '1' || value.toLowerCase() == 'true';
    } else if (entry.key.startsWith('H') || entry.key.length > 4) {
      _range(value, entry.key == 'ContentPaddingAddition' ? 65507 : 0xFFFFFFFF);
      awg[entry.value] = value;
    } else {
      awg[entry.value] = _number(value, 0, entry.key == 'Jc' ? 128 : 65507);
    }
  }
  if (awg.isEmpty) throw _invalid;
  if ((awg['jmin'] as int? ?? 0) > (awg['jmax'] as int? ?? 0)) throw _invalid;
  return {
    'type': 'awg', 'tag': 'Mit-AWG',
    'private_key': _key(local['PrivateKey'] ?? ''),
    'address': _prefixes(local['Address'] ?? ''),
    'mtu': _number(local['MTU'] ?? '1280', 576, 9000),
    if (local['ListenPort'] case final listen?) 'listen_port': _number(listen, 0, 65535),
    'awg': awg,
    'peers': [{
      'address': host, 'port': port,
      'public_key': _key(peer['PublicKey'] ?? ''),
      if (peer['PresharedKey'] case final psk?) 'preshared_key': _key(psk, allowZero: true),
      'allowed_ips': _prefixes(peer['AllowedIPs'] ?? '0.0.0.0/0,::/0'),
      'persistent_keepalive_interval': _number(peer['PersistentKeepalive'] ?? '0', 0, 65535),
    }],
  };
}

void _validatePacketTemplate(String value) {
  if (value.length > 8192) throw _invalid;
  var offset = 0;
  var size = 0;
  for (final tag in RegExp(r'<([^<>]+)>').allMatches(value)) {
    if (value.substring(offset, tag.start).trim().isNotEmpty) throw _invalid;
    final parts = tag.group(1)!.trim().split(RegExp(r'\s+'));
    final name = parts.first;
    if (name == 'b' && parts.length == 2) {
      final hex = parts[1].replaceFirst(RegExp(r'^0x'), '');
      if (hex.isEmpty || hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) throw _invalid;
      size += hex.length ~/ 2;
    } else if ({'r', 'rc', 'rd', 'dz'}.contains(name) && parts.length == 2) {
      // Native builders accept an arbitrary signed int, then allocate/slice
      // using it during a handshake. Bound every part and the complete packet.
      size += _number(parts[1], 0, 65507);
    } else if ({'t', 'd', 'ds'}.contains(name) && parts.length == 1) {
      size += name == 't' ? 4 : 0; // I packets have no source data.
    } else if (name == 'qi' && parts.length == 2 && _validHost(parts[1])) {
      size += 1200;
    } else {
      throw _invalid;
    }
    if (size > 65507) throw _invalid;
    offset = tag.end;
  }
  if (offset == 0 || value.substring(offset).trim().isNotEmpty) throw _invalid;
}

String _key(String text, {bool allowZero = false}) {
  if (!RegExp(r'^[A-Za-z0-9+/_-]{43}=?$').hasMatch(text)) throw _invalid;
  final bytes = _decodeBase64(text);
  if (bytes.length != 32 || (!allowZero && bytes.every((b) => b == 0))) throw _invalid;
  final canonical = base64.encode(bytes);
  if (base64.normalize(text) != canonical) throw _invalid;
  return canonical;
}

int _number(String text, int min, int max) {
  if (!RegExp(r'^[0-9]{1,10}$').hasMatch(text)) throw _invalid;
  final value = int.parse(text);
  if (value < min || value > max) throw _invalid;
  return value;
}

void _range(String value, int maximum) {
  final parts = value.split('-');
  if (parts.length > 2 || _number(parts.first, 0, maximum) > _number(parts.last, 0, maximum)) throw _invalid;
}

List<String> _prefixes(String value) {
  final result = <String>[];
  for (final raw in value.split(',')) {
    final parts = raw.trim().split('/');
    final ip = InternetAddress.tryParse(parts.first);
    if (ip == null || parts.length > 2 || parts.first.contains('%')) throw _invalid;
    final bits = ip.type == InternetAddressType.IPv4 ? 32 : 128;
    final prefix = parts.length == 2 ? _number(parts.last, 0, bits) : bits;
    result.add('${ip.address}/$prefix');
  }
  return result;
}

bool _validHost(String host) => !host.contains('%') && (InternetAddress.tryParse(host) != null ||
    (host.length <= 253 && host.split('.').every((label) => label.length <= 63 &&
      RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$').hasMatch(label))));

String _uriHost(Uri uri) => uri.host.startsWith('[') && uri.host.endsWith(']')
    ? uri.host.substring(1, uri.host.length - 1) : uri.host;

String _awgLinkConfig(String text) {
  if (RegExp(r'\s').hasMatch(text)) throw _invalid;
  final uri = Uri.parse(text);
  final host = _uriHost(uri);
  if (uri.scheme != 'awg' || !uri.hasPort || !_validHost(host) ||
      (uri.path.isNotEmpty && uri.path != '/')) throw _invalid;
  final aliases = <String, String>{
    'pk': 'PrivateKey', 'privatekey': 'PrivateKey',
    'publickey': 'PublicKey', 'peerpublickey': 'PublicKey', 'pub': 'PublicKey', 'peerpub': 'PublicKey', 'peerpk': 'PublicKey',
    'address': 'Address', 'ip': 'Address', 'localaddress': 'Address',
    'presharedkey': 'PresharedKey', 'psk': 'PresharedKey',
    'allowedips': 'AllowedIPs', 'keepalive': 'PersistentKeepalive', 'mtu': 'MTU', 'dns': 'DNS',
    for (final entry in _awgFields.entries) entry.key.toLowerCase(): entry.key,
    for (final entry in _awgFields.entries) entry.value: entry.key,
  };
  final values = <String, String>{};
  if (uri.userInfo.isNotEmpty) values['PrivateKey'] = Uri.decodeComponent(uri.userInfo);
  for (final entry in uri.queryParametersAll.entries) {
    final key = aliases[entry.key.toLowerCase()];
    if (key == null || entry.value.length != 1 || values.containsKey(key)) throw _invalid;
    final value = entry.value.single;
    if (RegExp(r'[\r\n\x00]').hasMatch(value)) throw _invalid;
    values[key] = value;
  }
  const peerFields = {'PublicKey', 'PresharedKey', 'AllowedIPs', 'PersistentKeepalive'};
  return '[Interface]\n${values.entries.where((e) => !peerFields.contains(e.key)).map((e) => '${e.key} = ${e.value}').join('\n')}\n'
      '[Peer]\nEndpoint = ${host.contains(':') ? '[$host]' : host}:${uri.port}\n'
      '${values.entries.where((e) => peerFields.contains(e.key)).map((e) => '${e.key} = ${e.value}').join('\n')}';
}
