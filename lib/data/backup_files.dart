import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final backupFilesProvider = Provider<BackupFiles>((ref) => BackupFiles());

/// Native document dialogs; no broad storage permission or typed paths.
class BackupFiles {
  /// Implemented in MainActivity.kt and MainFlutterWindow.swift.
  static const channel = MethodChannel('cohabit/files');

  Future<String?> openJson() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) return null;
    return utf8.decode(await result.readAsBytes());
  }

  /// Returns false if the user cancels. Throws unless the whole file reached
  /// storage; the native side confirms this after writing. macOS writes
  /// atomically, so a failed overwrite keeps the previous file.
  Future<bool> save(String contents, String extension) async {
    final saved = await channel.invokeMethod<bool>('saveDocument', {
      'fileName':
          'cohabit-${DateTime.now().toIso8601String().substring(0, 10)}.$extension',
      'mimeType': extension == 'json' ? 'application/json' : 'text/csv',
      'bytes': Uint8List.fromList(utf8.encode(contents)),
    });
    return saved ?? false;
  }
}
