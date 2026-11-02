import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup_files.dart';
import '../data/repository.dart';
import '../domain/hlc.dart';
import 'providers.dart';

/// Progress and the last result of a backup operation.
class BackupStatus {
  const BackupStatus({this.busy = false, this.message});

  final bool busy;
  final String? message;
}

/// Asks the user to confirm a restore. Returns whether to go ahead and
/// whether to restore the day-start time, or null to cancel.
typedef ConfirmRestore = Future<({bool restoreBoundary})?> Function(
  RestorePreview preview,
  int currentBoundary,
);

/// Runs backup operations above the page, so rotating or switching tabs
/// mid-operation can't drop a confirmed restore or lose its result.
class BackupController extends Notifier<BackupStatus> {
  @override
  BackupStatus build() => const BackupStatus();

  Future<void> save({required bool json}) => _run(() async {
    final repo = ref.read(repositoryProvider);
    final contents = json ? await repo.exportBackup() : await repo.exportCsv();
    final saved = await ref
        .read(backupFilesProvider)
        .save(contents, json ? 'json' : 'csv');
    return saved ? 'File saved.' : null;
  });

  Future<void> restore(ConfirmRestore confirm) => _run(() async {
    final repo = ref.read(repositoryProvider);
    final input = await ref.read(backupFilesProvider).openJson();
    if (input == null) return null;
    final preview = await repo.previewRestore(input);
    final current = await repo.dayBoundaryMinutes();
    final choice = await confirm(preview, current);
    if (choice == null) return null;
    await repo.restoreBackup(input, restoreBoundary: choice.restoreBoundary);
    return 'Restore complete. Backup merged with your data.';
  });

  Future<void> _run(Future<String?> Function() operation) async {
    if (state.busy) return;
    state = const BackupStatus(busy: true);
    String? message;
    try {
      message = await operation();
    } on ClockDriftException {
      message =
          'Check your device date and time, then try again. The backup '
          'contains events ahead of this device clock.';
    } on FormatException {
      message =
          'This file is not a supported Cohabit backup. Choose a valid JSON '
          'backup.';
    } catch (_) {
      message =
          'Could not complete the operation. Check the file and storage '
          'access, then try again.';
    }
    state = BackupStatus(message: message);
  }
}

final backupControllerProvider =
    NotifierProvider<BackupController, BackupStatus>(BackupController.new);
