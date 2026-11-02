import 'package:cohabit/design/theme.dart';

import 'package:cohabit/data/backup_files.dart';
import 'package:cohabit/data/database.dart';
import 'package:cohabit/data/repository.dart';
import 'package:cohabit/state/providers.dart';
import 'package:cohabit/ui/settings_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFiles extends BackupFiles {
  String? input;
  String? contents;
  String? extension;
  @override
  Future<String?> openJson() async => input;
  @override
  Future<bool> save(String contents, String extension) async {
    this.contents = contents;
    this.extension = extension;
    return true;
  }
}

void main() {
  testWidgets('exports and canceled or invalid restore at large font', (
    tester,
  ) async {
    final files = FakeFiles();
    late AppDatabase db;
    late CohabitRepository repo;
    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = await CohabitRepository.open(db);
    });
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          backupFilesProvider.overrideWithValue(files),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const SettingsPage(),
          ),
        ),
      ),
    );
    Future<void> tap(String label) async {
      await tester.scrollUntilVisible(find.text(label), 180);
      await tester.tap(find.text(label));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
    }

    await tap('Save backup (JSON)');
    expect(files.extension, 'json');
    expect(files.contents, contains('cohabit-backup'));
    await tap('Export CSV');
    expect(files.extension, 'csv');
    await tap('Restore backup');
    expect(find.text('Confirm restore'), findsNothing);
    files.input = 'invalid';
    await tap('Restore backup');
    expect(find.textContaining('not a supported'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(db.close);
  });
}
