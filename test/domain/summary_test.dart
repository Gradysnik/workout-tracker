import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/domain/models.dart';
import 'package:workout_tracker/domain/summary.dart';

ProgramExercise ex(ExerciseType t) =>
    ProgramExercise(workout: 'A', order: 1, name: 'X', type: t, sets: 2);

JournalRow row({double? w, int? r, int? s, double? m}) => JournalRow(
    id: '${w}_${r}_${s}_$m', date: DateTime.utc(2026, 11, 17), workout: 'A',
    exercise: 'X', setNo: 1, partNo: 1, weight: w, reps: r, seconds: s, minutes: m);

void main() {
  test('силовые сравниваются по объёму', () {
    final s = summarize([
      (exercise: ex(ExerciseType.strength),
          today: [row(w: 50, r: 10), row(w: 50, r: 8)],
          last: [row(w: 40, r: 10)]),
    ]);
    final r = s.results.single;
    expect((r.value, r.previous, r.delta), (900, 400, 500));
    expect(r.percent, 125);
    expect((s.improved, s.compared), (1, 1));
  });
  test('без прошлого раза нет сравнения', () {
    final s = summarize([
      (exercise: ex(ExerciseType.timed), today: [row(s: 40)], last: <JournalRow>[]),
    ]);
    expect(s.results.single.delta, isNull);
    expect(s.compared, 0);
  });
  test('упражнения без подходов пропускаются, кардио считается в минутах', () {
    final s = summarize([
      (exercise: ex(ExerciseType.strength), today: <JournalRow>[], last: [row(w: 1, r: 1)]),
      (exercise: ex(ExerciseType.cardio), today: [row(m: 12)], last: [row(m: 15)]),
    ]);
    expect(s.results.length, 1);
    expect(s.results.single.delta, -3);
    expect(s.improved, 0);
  });
}
