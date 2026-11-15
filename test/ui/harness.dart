import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workout_tracker/data/memory_stores.dart';
import 'package:workout_tracker/domain/models.dart';
import 'package:workout_tracker/providers.dart';
import 'package:workout_tracker/sheets/sync_service.dart';

const wA = 'Спина + Бицепс', wB = 'Грудь + Трицепс', wC = 'Ноги + Кор';
const rowing = ProgramExercise(workout: wA, order: 1, name: 'Гребной тренажёр', type: ExerciseType.cardio, sets: 1, note: '5 минут.');
const pulldown = ProgramExercise(workout: wA, order: 2, name: 'Тяга верхнего блока', type: ExerciseType.strength, sets: 4, repsTarget: '8–10', weightStep: 5);
const seatedRow = ProgramExercise(workout: wA, order: 3, name: 'Тяга горизонтального блока', type: ExerciseType.strength, sets: 4, repsTarget: '8–10', dropSet: true, weightStep: 5);
const bench = ProgramExercise(workout: wB, order: 1, name: 'Жим гантелей лёжа', type: ExerciseType.strength, sets: 4, repsTarget: '8–10');
const plank = ProgramExercise(workout: wB, order: 2, name: 'Планка', type: ExerciseType.timed, sets: 3, repsTarget: '30–45');
const rdl = ProgramExercise(workout: wC, order: 1, name: 'Румынская тяга', type: ExerciseType.strength, sets: 4, repsTarget: '8–10');

DateTime nov(int day) => DateTime.utc(2026, 11, day);

var _id = 0;
JournalRow jr(int day, ProgramExercise e, int setNo,
        {int part = 1, double? w, int? r, int? s, double? m, int? k, String note = ''}) =>
    JournalRow(id: 't${_id++}', date: nov(day), workout: e.workout, exercise: e.name,
        setNo: setNo, partNo: part, weight: w, reps: r, seconds: s, minutes: m, kcal: k, note: note);

class Harness {
  final journal = MemoryJournalStore();
  final program = MemoryProgramStore();
  final meta = MemoryMetaStore();
  DateTime today = nov(17);
  SyncService? sync;

  /// Программа на три дня и тренировки прошлой недели (10, 12 и 14 ноября).
  Future<void> seed() async {
    await program.replace(const [seatedRow, rowing, pulldown, bench, plank, rdl], const [
      ScheduleEntry(weekday: DateTime.tuesday, workout: wA),
      ScheduleEntry(weekday: DateTime.thursday, workout: wB),
      ScheduleEntry(weekday: DateTime.saturday, workout: wC),
    ]);
    for (final r in [
      jr(10, rowing, 1, m: 5, k: 71),
      jr(10, pulldown, 1, w: 40, r: 10), jr(10, pulldown, 2, w: 55, r: 10),
      jr(10, pulldown, 3, w: 55, r: 10), jr(10, pulldown, 4, w: 60, r: 10),
      jr(10, seatedRow, 1, w: 40, r: 10), jr(10, seatedRow, 2, w: 60, r: 10),
      jr(10, seatedRow, 3, w: 60, r: 10),
      jr(10, seatedRow, 4, w: 60, r: 10), jr(10, seatedRow, 4, part: 2, w: 40, r: 10),
      jr(12, bench, 1, w: 40, r: 10), jr(12, plank, 1, s: 40),
      jr(14, rdl, 1, w: 40, r: 10),
      jr(3, pulldown, 1, w: 40, r: 10), jr(3, pulldown, 2, w: 50, r: 10),
    ]) {
      await journal.upsert(r);
    }
    await journal.markSynced((await journal.pending()).map((p) => p.row.id));
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        journalStoreProvider.overrideWithValue(journal),
        programStoreProvider.overrideWithValue(program),
        metaStoreProvider.overrideWithValue(meta),
        clockProvider.overrideWithValue(() => today),
        syncServiceProvider.overrideWithValue(sync),
      ],
      child: MaterialApp(home: home),
    ));
    await tester.pumpAndSettle();
  }
}
