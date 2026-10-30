import 'dart:convert';

/// The pilot accepts one explicit VLESS/TCP/REALITY link, never a remote
/// subscription or arbitrary JSON with provider-controlled routing overrides.
/// Errors deliberately contain neither the input nor Uri parsing exceptions.
String validateRealityProfile(String input) {
  const error = FormatException('Требуется корректная ссылка VLESS + REALITY (TCP).');
  try {
    final text = input.trim();
    if (text.length > 8192 || RegExp(r'\s').hasMatch(text)) throw error;
    final uri = Uri.parse(text);
    final params = uri.queryParameters;
    const allowed = {'security', 'type', 'encryption', 'flow', 'sni', 'fp', 'pbk', 'sid', 'spx'};
    if (uri.scheme != 'vless' || uri.host.isEmpty || !uri.hasPort || uri.port < 1 || uri.port > 65535 ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        !RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$').hasMatch(uri.userInfo) ||
        uri.queryParametersAll.entries.any((e) => !allowed.contains(e.key) || e.value.length != 1) ||
        params['security'] != 'reality' || (params['type'] ?? 'tcp') != 'tcp' ||
        (params['encryption'] ?? 'none') != 'none' ||
        !{'', 'xtls-rprx-vision'}.contains(params['flow'] ?? '') ||
        !_validServerName(params['sni'] ?? '') ||
        !{'chrome', 'firefox', 'safari', 'ios', 'android', 'edge', 'random', 'randomized'}.contains(params['fp']) ||
        !RegExp(r'^(?:[0-9a-fA-F]{2}){0,8}$').hasMatch(params['sid'] ?? '') ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(params['pbk'] ?? '') ||
        base64Url.decode(base64Url.normalize(params['pbk']!)).length != 32) {
      throw error;
    }
    return text;
  } catch (_) {
    throw error;
  }
}

bool _validServerName(String value) {
  if (value.isEmpty || value.length > 253) return false;
  return value.split('.').every(
    (label) => label.length <= 63 && RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$').hasMatch(label),
  );
}
