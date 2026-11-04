import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/one_tap/mit_updates.dart';
import 'package:hiddify/features/one_tap/mit_windows_updates.dart';

void main() {
  final bytes = Uint8List.fromList([77, 90, 1, 2, 3, 4]);
  const tag = 'mit-windows-1.6.0-beta.1';
  const name = 'MitsVPN-1.6.0-beta.1-Windows-x64-Setup.exe';
  Map<String, dynamic> manifest() => {
    'schema': 1,
    'app_id': 'com.mitsvpn.app',
    'platform': 'windows',
    'architecture': 'x64',
    'version': '1.6.0-beta.1',
    'build_number': 10502,
    'setup_filename': name,
    'setup_size': bytes.length,
    'setup_sha256': sha256.convert(bytes).toString(),
  };
  Map<String, dynamic> release() => {
    'draft': false,
    'tag_name': tag,
    'body': 'Windows update',
    'assets': [
      {'name': name, 'browser_download_url': mitReleaseAsset(tag, name).toString()},
    ],
  };

  test('Windows manifest requires this app, x64, matching tag and canonical EXE asset', () {
    final update = parseMitWindowsUpdate(release(), manifest())!;
    expect(update.version, '1.6.0-beta.1');
    expect(parseMitWindowsUpdate(release(), manifest(), currentBuild: 10502), isNull);
    for (final invalid in [
      {...manifest(), 'platform': 'android'},
      {...manifest(), 'architecture': 'arm64'},
      {...manifest(), 'app_id': 'another.app'},
      {...manifest(), 'setup_filename': '../setup.exe'},
      {...manifest(), 'setup_size': mitMaxWindowsUpdateBytes + 1},
      {...manifest(), 'setup_sha256': 'bad'},
    ]) {
      expect(() => parseMitWindowsUpdate(release(), invalid), throwsA(isA<MitUpdateException>()));
    }
    expect(() => parseMitWindowsUpdate({...release(), 'draft': true}, manifest()), throwsA(isA<MitUpdateException>()));
    expect(
      () => parseMitWindowsUpdate({...release(), 'tag_name': 'mit-windows-1.7.0-beta.1'}, manifest()),
      throwsA(isA<MitUpdateException>()),
    );
    expect(
      () => parseMitWindowsUpdate({
        ...release(),
        'assets': [
          {'name': name, 'browser_download_url': 'https://evil.test/setup.exe'},
        ],
      }, manifest()),
      throwsA(isA<MitUpdateException>()),
    );
  });

  test('verified download preserves exact bytes; hash mismatch and cancellation remove temporary files', () async {
    final root = await Directory.systemTemp.createTemp('mit-windows-update-test-');
    addTearDown(() => root.delete(recursive: true));
    var payload = bytes;
    final dio = Dio()..httpClientAdapter = _BytesAdapter(() => payload);
    addTearDown(() => dio.close(force: true));
    final service = MitWindowsUpdateService(MitUpdateService(dio));
    final update = parseMitWindowsUpdate(release(), manifest())!;
    final file = await service.download(update, root, CancelToken(), (_, _) {});
    expect(await file.readAsBytes(), bytes);
    await file.parent.delete(recursive: true);
    payload = Uint8List.fromList([77, 90, 1, 2, 3, 9]);
    await expectLater(service.download(update, root, CancelToken(), (_, _) {}), throwsA(isA<MitUpdateException>()));
    expect(await root.list().toList(), isEmpty);
    payload = bytes;
    final token = CancelToken();
    await expectLater(service.download(update, root, token, (_, _) => token.cancel()), throwsA(anything));
    expect(await root.list().toList(), isEmpty);
  });
}

class _BytesAdapter implements HttpClientAdapter {
  _BytesAdapter(this.payload);
  final Uint8List Function() payload;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancelFuture) async =>
      ResponseBody(Stream.value(payload()), 200);
  @override
  void close({bool force = false}) {}
}
