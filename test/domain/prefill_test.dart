import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/domain/models.dart';
import 'package:workout_tracker/domain/prefill.dart';

ProgramExercise ex({ExerciseType type = ExerciseType.strength, String reps = '8–10'}) =>
    ProgramExercise(workout: 'A', order: 1, name: 'Тяга', type: type, sets: 4, repsTarget: reps);

JournalRow row(int setNo, {int part = 1, double? w, int? r, int? s, double? m, int? k, int day = 10}) =>
    JournalRow(id: '$day-$setNo-$part', date: DateTime.utc(2026, 11, day), workout: 'A',
        exercise: 'Тяга', setNo: setNo, partNo: part, weight: w, reps: r, seconds: s, minutes: m, kcal: k);

void main() {
  test('берёт первую часть того же подхода прошлой тренировки', () {
    final d = prefillSet(exercise: ex(), setNo: 2, today: [], lastSession: [
      row(1, w: 40, r: 10), row(2, w: 60, r: 9), row(2, part: 2, w: 40, r: 8),
    ]);
    expect((d.weight, d.reps), (60, 9));
  });
  test('если подхода в прошлый раз не было — предыдущий подход сегодня', () {
    final d = prefillSet(exercise: ex(), setNo: 3,
        today: [row(1, w: 45, r: 10, day: 17), row(2, w: 50, r: 8, day: 17)],
        lastSession: [row(1, w: 40, r: 10)]);
    expect((d.weight, d.reps), (50, 8));
  });
  test('без истории — вес 0 и нижняя граница цели', () {
    final d = prefillSet(exercise: ex(), setNo: 1, today: [], lastSession: []);
    expect((d.weight, d.reps), (0, 8));
  });
  test('пустая цель — 0 повторов', () {
    final d = prefillSet(exercise: ex(reps: ''), setNo: 1, today: [], lastSession: []);
    expect(d.reps, 0);
  });
  test('для упражнения на время заполняет секунды', () {
    final d = prefillSet(exercise: ex(type: ExerciseType.timed, reps: '30–45'), setNo: 1,
        today: [], lastSession: [row(1, s: 40)]);
    expect(d.seconds, 40);
    final empty = prefillSet(exercise: ex(type: ExerciseType.timed, reps: '30–45'), setNo: 1,
        today: [], lastSession: []);
    expect(empty.seconds, 30);
  });
  test('для кардио заполняет минуты и ккал', () {
    final d = prefillSet(exercise: ex(type: ExerciseType.cardio, reps: ''), setNo: 1,
        today: [], lastSession: [row(1, m: 5, k: 71)]);
    expect((d.minutes, d.kcal), (5, 71));
  });
  ProgramExercise cardio({String reps = '', String note = ''}) => ProgramExercise(
      workout: 'A', order: 1, name: 'Бег', type: ExerciseType.cardio, sets: 1,
      repsTarget: reps, note: note);
  test('кардио без истории берёт минуты из примечания', () {
    final d = prefillSet(exercise: cardio(note: '10 минут'), setNo: 1,
        today: [], lastSession: []);
    expect((d.minutes, d.kcal), (10, 0));
  });
  test('кардио: номер подхода не совпал — берём прошлый результат', () {
    final d = prefillSet(exercise: cardio(note: '5 минут'), setNo: 2,
        today: [], lastSession: [row(1, m: 12, k: 90)]);
    expect((d.minutes, d.kcal), (12, 90));
  });
  test('кардио: в прошлый раз минут не было — цель из программы', () {
    final d = prefillSet(exercise: cardio(reps: '15'), setNo: 1,
        today: [], lastSession: [row(1, k: 90)]);
    expect((d.minutes, d.kcal), (15, 90));
  });
}
