import 'dart:io';

import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/features/one_tap/report/mit_connection_journal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

final mitErrorReportsEnabledProvider = Provider<bool>((ref) => Platform.isAndroid);

final mitConnectionJournalProvider = Provider<MitConnectionJournal>((ref) {
  final file = ref
      .read(appDirectoriesProvider.future)
      .then((dirs) => File(p.join(dirs.baseDir.path, 'last-connection-report.json')));
  final journal = MitConnectionJournal(file: () => file);
  ref.onDispose(journal.dispose);
  return journal;
});
