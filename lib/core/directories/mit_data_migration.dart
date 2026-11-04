import 'dart:io';

import 'package:path/path.dart' as p;

/// Copy into a private staging directory, then atomically publish the complete
/// copy. Never overwrite new-version data or remove the original directory.
Future<void> migrateMitWindowsData(Directory legacy, Directory destination) async {
  if (!await legacy.exists()) return;
  if (await destination.exists() && !await destination.list().isEmpty) return;
  await destination.parent.create(recursive: true);
  final staging = await destination.parent.createTemp('mits-vpn-migration-');
  try {
    await for (final entity in legacy.list(recursive: true, followLinks: false)) {
      final target = p.join(staging.path, p.relative(entity.path, from: legacy.path));
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await File(target).parent.create(recursive: true);
        await entity.copy(target);
      }
    }
    if (await destination.exists()) {
      if (!await destination.list().isEmpty) return;
      await destination.delete();
    }
    await staging.rename(destination.path);
  } finally {
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
