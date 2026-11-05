// Run with fastforge's package_config.json so this tests the real packager.
import 'dart:io';

import 'package:flutter_app_packager/src/makers/exe/inno_setup/inno_setup_script.dart';
import 'package:flutter_app_packager/src/makers/exe/make_exe_config.dart';
import 'package:yaml/yaml.dart';

Future<void> main() async {
  final values = Map<String, dynamic>.from(
    loadYaml(File('windows/packaging/exe/make_config.yaml').readAsStringSync()) as Map,
  );
  if (values['executable_name'] != 'MitsVPN.exe') {
    throw StateError('Installer must explicitly select MitsVPN.exe, never the first EXE in the folder.');
  }
  final temporary = await Directory.systemTemp.createTemp('mits-installer-regression-');
  try {
    final config = MakeExeConfig.fromJson(values)
      ..platform = 'windows'
      ..packageFormat = 'exe'
      ..buildMode = 'release'
      ..isInstaller = true
      ..outputDirectory = temporary;
    final payload = config.packagingDirectory;
    for (final executable in ['HiddifyAdmin.exe', 'HiddifyCli.exe', 'MitsVPN.exe']) {
      File('${payload.path}/$executable').writeAsStringSync('synthetic packager fixture');
    }
    final inferred = config.defaultExecutableName;
    stdout.writeln('Unspecified executable would select: $inferred');
    final rendered = await InnoSetupScript.fromMakeConfig(config).createFile();
    final content = await rendered.readAsString();
    final entries = content.split('\n').where((line) => line.contains('Filename:') && line.contains('{app}'));
    if (entries.length != 4) throw StateError('Expected three shortcuts and the post-install launch.');
    for (final line in entries) {
      if (!line.contains('MitsVPN.exe') || line.contains('HiddifyAdmin.exe') || line.contains('HiddifyCli.exe')) {
        throw StateError('Wrong installer entry point: $line');
      }
      if (!line.contains('WorkingDir: "{app}"')) throw StateError('Missing working directory: $line');
      if (line.startsWith('Name:') && (!line.contains('IconFilename:') || !line.contains('IconIndex: 0'))) {
        throw StateError('Shortcut must explicitly use the application icon: $line');
      }
    }
    if (!content.contains('UninstallDisplayIcon={app}\\MitsVPN.exe')) {
      throw StateError('Missing branded uninstall icon.');
    }
    stdout.writeln('Actual Inno template: all shortcut, launch and icon targets select MitsVPN.exe.');
  } finally {
    await temporary.delete(recursive: true);
  }
}
