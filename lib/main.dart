import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await CohabitRepository.open(AppDatabase.persistent());
  runApp(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repository)],
      child: const CohabitApp(),
    ),
  );
}
