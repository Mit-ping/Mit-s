import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/directories/mit_data_migration.dart';
import 'package:path/path.dart' as p;

void main() {
  test('migration preserves original profiles and preferences and never replaces new data', () async {
    final root = await Directory.systemTemp.createTemp('mit-migration-test-');
    addTearDown(() => root.delete(recursive: true));
    final legacy = Directory(p.join(root.path, 'old'))..createSync();
    final destination = Directory(p.join(root.path, 'new'))..createSync();
    final profile = File(p.join(legacy.path, 'profiles', 'profile.json'));
    await profile.parent.create();
    await profile.writeAsString('synthetic-profile');
    await File(p.join(legacy.path, 'preferences.json')).writeAsString('synthetic-preferences');
    await migrateMitWindowsData(legacy, destination);
    final migrated = File(p.join(destination.path, 'profiles', 'profile.json'));
    expect(await migrated.readAsString(), 'synthetic-profile');
    expect(await profile.readAsString(), 'synthetic-profile');
    expect(await File(p.join(destination.path, 'preferences.json')).readAsString(), 'synthetic-preferences');
    await migrated.writeAsString('new-version-data');
    await migrateMitWindowsData(legacy, destination);
    expect(await migrated.readAsString(), 'new-version-data');
    expect(
      await root.list().where((entry) => p.basename(entry.path).startsWith('mits-vpn-migration-')).toList(),
      isEmpty,
    );
  });
}
