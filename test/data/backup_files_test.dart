import 'package:cohabit/data/backup_files.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void reply(Future<Object?> Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(BackupFiles.channel, handler);
    addTearDown(
      () => messenger.setMockMethodCallHandler(BackupFiles.channel, null),
    );
  }

  test('sends the name, type and UTF-8 bytes', () async {
    late Map<Object?, Object?> args;
    reply((call) async {
      args = call.arguments as Map<Object?, Object?>;
      return true;
    });
    expect(await BackupFiles().save('é', 'csv'), isTrue);
    expect(args['mimeType'], 'text/csv');
    expect(args['fileName'], matches(RegExp(r'^cohabit-.*\.csv$')));
    expect(args['bytes'], [0xC3, 0xA9]);
  });

  test('cancelling is not a success', () async {
    reply((_) async => false);
    expect(await BackupFiles().save('x', 'json'), isFalse);
  });

  test('an unverified write is an error, not a saved file', () async {
    reply((_) async => throw PlatformException(code: 'write_failed'));
    expect(BackupFiles().save('x', 'json'), throwsA(isA<PlatformException>()));
  });
}
