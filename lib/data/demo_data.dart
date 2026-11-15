import '../domain/models.dart';
import 'stores.dart';

const _back = 'Спина + Бицепс';
const _chest = 'Грудь + Трицепс';
const _legs = 'Ноги + Кор';

ProgramExercise _s(String workout, int order, String name, int sets, String reps,
        {bool drop = false, double step = 2.5}) =>
    ProgramExercise(workout: workout, order: order, name: name,
        type: ExerciseType.strength, sets: sets, repsTarget: reps,
        dropSet: drop, weightStep: step);

final demoProgram = [
  const ProgramExercise(workout: _back, order: 1, name: 'Гребной тренажёр',
      type: ExerciseType.cardio, sets: 1, note: '5 минут'),
  _s(_back, 2, 'Тяга верхнего блока к груди (широкий)', 4, '8–10', step: 5),
  _s(_back, 3, 'Тяга горизонтального блока (узкий хват)', 4, '8–10', drop: true, step: 5),
  _s(_back, 4, 'Face pulls сверху', 3, '10–15'),
  _s(_back, 5, 'Сгибания рук с гантелями', 3, '8–10', step: 1),
  const ProgramExercise(workout: _chest, order: 1, name: 'Эллипс',
      type: ExerciseType.cardio, sets: 1, note: '5 минут'),
  _s(_chest, 2, 'Жим гантелей лёжа', 4, '8–10', step: 5),
  _s(_chest, 3, 'Жим в Смите на наклонной скамье', 4, '8–10', drop: true, step: 5),
  _s(_chest, 4, 'Французский жим с гантелью', 3, '8–10'),
  const ProgramExercise(workout: _chest, order: 5, name: 'Планка с подъёмом ног',
      type: ExerciseType.timed, sets: 3, repsTarget: '30–45'),
  _s(_legs, 1, 'Сгибания ног сидя', 4, '10–12', drop: true, step: 5),
  _s(_legs, 2, 'Румынская тяга с гантелями', 4, '8–10', step: 5),
  _s(_legs, 3, 'Выпады назад с гантелями', 3, '10', step: 5),
];

const demoSchedule = [
  ScheduleEntry(weekday: DateTime.tuesday, workout: _back),
  ScheduleEntry(weekday: DateTime.thursday, workout: _chest),
  ScheduleEntry(weekday: DateTime.saturday, workout: _legs),
];

/// Образец данных для демо-режима: программа и шесть недель тренировок
/// с плавно растущими весами, заканчивая последней прошедшей тренировкой.
Future<void> seedDemo(
    JournalStore journal, ProgramStore program, DateTime today) async {
  await program.replace(demoProgram, demoSchedule);
  today = dateOnly(today);
  final rows = <JournalRow>[];
  var n = 0;
  for (var back = 42; back >= 1; back--) {
    final date = today.subtract(Duration(days: back));
    final entry = demoSchedule.where((s) => s.weekday == date.weekday);
    if (entry.isEmpty) continue;
    final week = (42 - back) ~/ 7;
    for (final e in demoProgram.where((e) => e.workout == entry.first.workout)) {
      JournalRow row(int setNo, int part,
              {double? w, int? r, int? s, double? m, int? k}) =>
          JournalRow(id: 'demo-${n++}', date: date, workout: e.workout,
              exercise: e.name, setNo: setNo, partNo: part, weight: w,
              reps: r, seconds: s, minutes: m, kcal: k);
      switch (e.type) {
        case ExerciseType.cardio:
          rows.add(row(1, 1, m: 5, k: 55 + week * 3));
        case ExerciseType.timed:
          for (var i = 1; i <= e.sets; i++) {
            rows.add(row(i, 1, s: 30 + week * 2));
          }
        case ExerciseType.strength:
          final base = 20 + e.order * 5 + week * e.weightStep;
          for (var i = 1; i <= e.sets; i++) {
            final w = base + (i > 1 ? e.weightStep * 2 : 0);
            rows.add(row(i, 1, w: w, r: 10));
            if (e.dropSet && i == e.sets) {
              rows.add(row(i, 2, w: w - e.weightStep * 4, r: 10));
            }
          }
      }
    }
  }
  await journal.replaceAll(rows);
}
