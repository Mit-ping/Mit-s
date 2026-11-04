import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hiddify/features/one_tap/mit_release.dart';
import 'package:hiddify/features/one_tap/mit_updates.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const mitMaxWindowsUpdateBytes = 450 * 1024 * 1024;
const mitWindowsManifestName = 'mits-vpn-windows-update.json';

class MitWindowsUpdate {
  const MitWindowsUpdate({
    required this.version,
    required this.build,
    required this.notes,
    required this.filename,
    required this.url,
    required this.hash,
    required this.size,
  });
  final String version, notes, filename, hash;
  final int build, size;
  final Uri url;
}

MitWindowsUpdate? parseMitWindowsUpdate(Map release, Map manifest, {int currentBuild = MitRelease.windowsBuild}) {
  final version = manifest['version'];
  final tag = release['tag_name'];
  final build = manifest['build_number'];
  final size = manifest['setup_size'];
  final hash = manifest['setup_sha256'];
  final filename = manifest['setup_filename'];
  if (release['draft'] != false ||
      version is! String ||
      !RegExp(r'^\d+\.\d+\.\d+-beta\.\d+$').hasMatch(version) ||
      tag != 'mit-windows-$version' ||
      manifest['schema'] != 1 ||
      manifest['app_id'] != 'com.mitsvpn.app' ||
      manifest['platform'] != 'windows' ||
      manifest['architecture'] != 'x64' ||
      build is! int ||
      build <= 0 ||
      build > 2147483647 ||
      size is! int ||
      size <= 0 ||
      size > mitMaxWindowsUpdateBytes ||
      hash is! String ||
      !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
      filename != 'MitsVPN-$version-Windows-x64-Setup.exe')
    throw const MitUpdateException();
  final url = mitReleaseAsset(tag as String, filename as String);
  final assets = release['assets'];
  if (assets is! List ||
      !assets.whereType<Map>().any((a) => a['name'] == filename && a['browser_download_url'] == url.toString()))
    throw const MitUpdateException();
  if (build <= currentBuild) return null;
  final notes = release['body'] is String ? release['body'] as String : '';
  return MitWindowsUpdate(
    version: version,
    build: build,
    filename: filename,
    url: url,
    notes: notes.length > 8000 ? notes.substring(0, 8000) : notes,
    hash: hash.toLowerCase(),
    size: size,
  );
}

class MitWindowsUpdateService {
  MitWindowsUpdateService(this.transport);
  final MitUpdateService transport;
  Future<MitWindowsUpdate?> check(CancelToken token) async {
    final data = await transport.readJson(
      Uri.https('api.github.com', '/repos/$mitUpdateRepository/releases', {'per_page': '20'}),
      token,
    );
    if (data is! List) throw const MitUpdateException();
    MitWindowsUpdate? best;
    for (final release in data.whereType<Map>()) {
      final tag = release['tag_name'];
      if (release['draft'] != false ||
          tag is! String ||
          !RegExp(r'^mit-windows-\d+\.\d+\.\d+-beta\.\d+$').hasMatch(tag))
        continue;
      final assets = release['assets'];
      if (assets is! List ||
          !assets.whereType<Map>().any(
            (a) =>
                a['name'] == mitWindowsManifestName &&
                a['browser_download_url'] == mitReleaseAsset(tag, mitWindowsManifestName).toString(),
          ))
        continue;
      final manifest = await transport.readJson(mitReleaseAsset(tag, mitWindowsManifestName), token);
      if (manifest is! Map) throw const MitUpdateException();
      final update = parseMitWindowsUpdate(release, manifest);
      if (update != null && (best == null || update.build > best.build)) best = update;
    }
    return best;
  }

  Future<File> download(
    MitWindowsUpdate update,
    Directory directory,
    CancelToken token,
    void Function(int received, int total) progress,
  ) async {
    await directory.create(recursive: true);
    // Unique temporary paths keep cancelled or concurrent downloads isolated.
    final temporary = await directory.createTemp('download-');
    final partial = File(p.join(temporary.path, 'setup.part'));
    final output = File(p.join(temporary.path, 'setup.exe'));
    final sink = partial.openWrite();
    var received = 0;
    try {
      final body = await transport.streamResponse(update.url, token);
      await for (final bytes in body.stream) {
        if (token.isCancelled) throw token.cancelError!;
        received += bytes.length;
        if (received > update.size || received > mitMaxWindowsUpdateBytes) throw const MitUpdateException();
        sink.add(bytes);
        progress(received, update.size);
      }
      await sink.flush();
      await sink.close();
      if (token.isCancelled ||
          received != update.size ||
          (await sha256.bind(partial.openRead()).first).toString() != update.hash)
        throw const MitUpdateException();
      await partial.rename(output.path);
      return output;
    } catch (_) {
      await sink.close();
      if (await temporary.exists()) await temporary.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> install(MitWindowsUpdate update, File file) async {
    if (!Platform.isWindows ||
        await file.length() != update.size ||
        (await sha256.bind(file.openRead()).first).toString() != update.hash)
      throw const MitUpdateException();
    // User explicitly confirms installation; the normal installer may show UAC.
    await Process.start(file.path, const [], mode: ProcessStartMode.detached, runInShell: false);
  }

  Future<Directory> directory() async => Directory(p.join((await getApplicationSupportDirectory()).path, 'updates'));
}

final mitWindowsUpdateServiceProvider = Provider<MitWindowsUpdateService>(
  (ref) => MitWindowsUpdateService(ref.watch(mitUpdateServiceProvider)),
);
