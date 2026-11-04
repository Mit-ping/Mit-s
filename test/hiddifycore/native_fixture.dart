import 'dart:io';

/// The Go core keeps Windows log handles until the test worker exits. The parent
/// CI step owns and deletes this directory after all Flutter workers finish.
Future<Directory> createNativeFixture(String prefix) async {
  final parent = Platform.environment['MIT_NATIVE_TEST_DIRECTORY'];
  if (Platform.isWindows && parent == null) {
    throw StateError('Set MIT_NATIVE_TEST_DIRECTORY and remove it after the Flutter test process exits.');
  }
  final directory = Directory(parent ?? Directory.systemTemp.path);
  await directory.create(recursive: true);
  return directory.createTemp(prefix);
}

Future<void> cleanNativeFixture(Directory directory) async {
  if (!Platform.isWindows) await directory.delete(recursive: true);
}
