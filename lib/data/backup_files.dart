import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final backupFilesProvider = Provider<BackupFiles>((ref) => BackupFiles());

/// Native document dialogs; no broad storage permission or typed paths.
class BackupFiles {
  Future<String?> openJson() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) return null;
    return utf8.decode(await result.readAsBytes());
  }

  Future<bool> save(String contents, String extension) async {
    final result = await FilePicker.saveFile(
      fileName:
          'cohabit-${DateTime.now().toIso8601String().substring(0, 10)}.$extension',
      mimeType: extension == "json" ? "application/json" : "text/csv",
      bytes: Uint8List.fromList(utf8.encode(contents)),
    );
    return result != null;
  }
}
