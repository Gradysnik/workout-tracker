import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/stores.dart';
import 'domain/exercise_key.dart';
import 'domain/models.dart';
import 'domain/today_selector.dart';
import 'sheets/google_auth.dart';
import 'sheets/sync_service.dart';

// Хранилища подставляются в main.dart (drift или демо) и в тестах.
final journalStoreProvider =
    Provider<JournalStore>((ref) => throw StateError('не настроено'));
final programStoreProvider =
    Provider<ProgramStore>((ref) => throw StateError('не настроено'));
final metaStoreProvider =
    Provider<MetaStore>((ref) => throw StateError('не настроено'));

/// null в демо-режиме: синхронизации нет.
final syncServiceProvider = Provider<SyncService?>((ref) => null);
final googleAuthProvider = Provider<GoogleAuth?>((ref) => null);

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Сегодняшняя дата без времени.
final todayDateProvider =
    Provider<DateTime>((ref) => dateOnly(ref.watch(clockProvider)()));

/// Растёт при любом изменении журнала или программы;
/// экраны следят за ним, чтобы перечитать данные.
final revisionProvider = StreamProvider<int>((ref) {
  final journal = ref.watch(journalStoreProvider);
  final program = ref.watch(programStoreProvider);
  return Stream.multi((controller) {
    var revision = 0;
    controller.add(revision);
    final subs = [
      journal.changes().listen((_) => controller.add(++revision)),
      program.changes().listen((_) => controller.add(++revision)),
    ];
    controller.onCancel = () {
      for (final s in subs) {
        s.cancel();
      }
    };
  });
});

/// Тренировка, выбранная вручную вместо предложенной.
class SelectedWorkout extends Notifier<String?> {
  @override
  String? build() {
    // Выбор действует только в течение дня: с новой датой сбрасывается.
    ref.watch(todayDateProvider);
    return null;
  }

  void select(String? workout) => state = workout;
}

final selectedWorkoutProvider =
    NotifierProvider<SelectedWorkout, String?>(SelectedWorkout.new);

class ExerciseStatus {
  const ExerciseStatus(this.exercise, this.today, this.last);
  final ProgramExercise exercise;
  final List<JournalRow> today;
  final List<JournalRow> last;

  int get setsDone => today.map((r) => r.setNo).toSet().length;
  bool get done => setsDone >= exercise.sets;
}

class TodayData {
  const TodayData({
    required this.date,
    required this.workouts,
    this.workout,
    this.choice,
    this.exercises = const [],
  });
  final DateTime date;

  /// Все тренировки программы в порядке появления.
  final List<String> workouts;

  /// Показанная тренировка; null, если программа пуста.
  final String? workout;
  final TodayChoice? choice;
  final List<ExerciseStatus> exercises;

  bool get manual =>
      choice == null || exerciseKey(choice!.workout) != exerciseKey(workout ?? '');
}

List<String> workoutsOf(List<ProgramExercise> program) {
  final seen = <String>{};
  return [
    for (final e in program)
      if (seen.add(exerciseKey(e.workout))) e.workout
  ];
}

List<ProgramExercise> exercisesOf(List<ProgramExercise> program, String workout) {
  final key = exerciseKey(workout);
  final list = [
    for (final e in program)
      if (exerciseKey(e.workout) == key) e
  ];
  // Стабильная сортировка по колонке «Порядок».
  final indexed = list.indexed.toList()
    ..sort((a, b) {
      final c = a.$2.order.compareTo(b.$2.order);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

/// Упражнения тренировки [workout] на дату [date] с подходами этого дня
/// и прошлой тренировки.
Future<List<ExerciseStatus>> loadExercises(JournalStore journal,
    List<ProgramExercise> program, String workout, DateTime date) async {
  final dayRows = await journal.rowsOn(date);
  final result = <ExerciseStatus>[];
  for (final e in exercisesOf(program, workout)) {
    final key = exerciseKey(e.name);
    result.add(ExerciseStatus(
      e,
      [for (final r in dayRows) if (exerciseKey(r.exercise) == key) r],
      await journal.lastSessionOf(key, before: date),
    ));
  }
  return result;
}

final todayProvider = FutureProvider<TodayData>((ref) async {
  ref.watch(revisionProvider);
  final journal = ref.watch(journalStoreProvider);
  final programStore = ref.watch(programStoreProvider);
  final date = ref.watch(todayDateProvider);
  final selected = ref.watch(selectedWorkoutProvider);

  final program = await programStore.program();
  final workouts = workoutsOf(program);
  if (workouts.isEmpty) return TodayData(date: date, workouts: workouts);

  final choice = chooseWorkout(
      today: date,
      schedule: await programStore.schedule(),
      sessions: await journal.sessions());
  String? pick(String? name) {
    if (name == null) return null;
    final key = exerciseKey(name);
    for (final w in workouts) {
      if (exerciseKey(w) == key) return w;
    }
    return null;
  }

  // Тренировка из расписания может отсутствовать в программе — тогда первая.
  final workout = pick(selected) ?? pick(choice?.workout) ?? workouts.first;
  return TodayData(
    date: date,
    workouts: workouts,
    workout: workout,
    choice: choice,
    exercises: await loadExercises(journal, program, workout, date),
  );
});

/// Запуск синхронизации из интерфейса: сразу или с задержкой после ввода.
class SyncRunner {
  SyncRunner(this._sync, this._auth);
  final SyncService? _sync;
  final GoogleAuth? _auth;
  Timer? _timer;

  final running = ValueNotifier<bool>(false);
  final lastReport = ValueNotifier<SyncReport?>(null);

  bool get available => _sync != null && (_auth == null || _auth.email != null);

  Future<SyncReport?> run() async {
    final sync = _sync;
    if (sync == null || !available) return null;
    running.value = true;
    try {
      return lastReport.value = await sync.syncAll();
    } finally {
      running.value = false;
    }
  }

  /// Отложенная отправка: несколько подходов подряд уходят одним запросом.
  void schedule() {
    if (!available) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), run);
  }

  void dispose() => _timer?.cancel();
}

final syncRunnerProvider = Provider<SyncRunner>((ref) {
  final runner = SyncRunner(
      ref.watch(syncServiceProvider), ref.watch(googleAuthProvider));
  ref.onDispose(runner.dispose);
  return runner;
});
