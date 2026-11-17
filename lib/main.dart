import 'dart:async';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'data/demo_data.dart';
import 'data/drift/database.dart';
import 'data/drift/drift_stores.dart';
import 'data/memory_stores.dart';
import 'providers.dart';
import 'sheets/google_auth.dart';
import 'sheets/google_sheets_gateway.dart';
import 'sheets/sync_service.dart';

/// Демо-режим: образец данных в памяти, без входа в Google.
/// Запуск: flutter run --dart-define=DEMO=true
const demoMode = bool.fromEnvironment('DEMO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (demoMode) {
    final journal = MemoryJournalStore();
    final program = MemoryProgramStore();
    await seedDemo(journal, program, DateTime.now());
    runApp(ProviderScope(overrides: [
      journalStoreProvider.overrideWithValue(journal),
      programStoreProvider.overrideWithValue(program),
      metaStoreProvider.overrideWithValue(MemoryMetaStore()),
    ], child: const WorkoutTrackerApp()));
    return;
  }

  final db = AppDatabase(driftDatabase(name: 'workout_tracker'));
  final journal = DriftJournalStore(db);
  final program = DriftProgramStore(db);
  final meta = DriftMetaStore(db);
  final auth = GoogleAuth(meta);
  final sync = SyncService(GoogleSheetsGateway(auth), journal, program, meta);

  final container = ProviderContainer(overrides: [
    journalStoreProvider.overrideWithValue(journal),
    programStoreProvider.overrideWithValue(program),
    metaStoreProvider.overrideWithValue(meta),
    googleAuthProvider.overrideWithValue(auth),
    syncServiceProvider.overrideWithValue(sync),
  ]);
  runApp(UncontrolledProviderScope(
      container: container, child: const WorkoutTrackerApp()));

  // Синхронизация в фоне: приложение сразу работает с локальными данными.
  unawaited(() async {
    if (await auth.signInSilently()) {
      await container.read(syncRunnerProvider).run();
    }
  }());
}
