import 'dart:io';

/// Android Mit release numbering is independent of upstream iOS/Windows versions.
abstract class MitRelease {
  static const label = 'Beta 1.5';
  static const buildName = '1.5.0-beta';
  static const buildNumber = 50005;
  static const windowsVersion = '1.5.0-beta.2';
  static const windowsBuild = 10501;
  static String get currentVersion => Platform.isWindows ? windowsVersion : buildName;
  static int get currentBuild => Platform.isWindows ? windowsBuild : buildNumber;
}
