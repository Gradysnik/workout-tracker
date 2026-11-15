import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/domain/models.dart';
import 'package:workout_tracker/ui/format.dart';

JournalRow row(int setNo, {int part = 1, double? w, int? r, int? s, double? m, int? k}) =>
    JournalRow(id: '$setNo-$part', date: DateTime.utc(2026, 11, 10), workout: 'A', exercise: 'E',
        setNo: setNo, partNo: part, weight: w, reps: r, seconds: s, minutes: m, kcal: k);

void main() {
  test('числа без лишних нулей и с запятой', () {
    expect(formatNumber(60), '60');
    expect(formatNumber(7.5), '7,5');
    expect(formatNumber(2.50), '2,5');
  });
  test('подходы: части дроп-сета через тире', () {
    expect(formatSets([row(1, w: 40, r: 10), row(2, w: 60, r: 10), row(2, part: 2, w: 40, r: 10)]),
        '40×10 · 60×10–40×10');
    expect(formatSets([row(1, r: 20), row(2, r: 20)]), '20 · 20');
    expect(formatSets([row(1, s: 30), row(2, s: 45)]), '30 с · 45 с');
    expect(formatSets([row(1, m: 5, k: 71)]), '5 мин · 71 ккал');
    expect(formatSets([row(1, k: 64)]), '64 ккал');
  });
  test('цель упражнения', () {
    ProgramExercise e(ExerciseType t, {bool drop = false, String reps = '8–10', String note = ''}) =>
        ProgramExercise(workout: 'A', order: 1, name: 'E', type: t, sets: 4, repsTarget: reps, dropSet: drop, note: note);
    expect(targetText(e(ExerciseType.strength, drop: true)), '4×8–10, дроп-сет');
    expect(targetText(e(ExerciseType.strength, reps: '')), '4 подхода');
    expect(targetText(e(ExerciseType.timed, reps: '30–45')), '4×30–45 с');
    expect(targetText(e(ExerciseType.cardio, note: '5 минут.')), '5 минут.');
    expect(targetText(e(ExerciseType.cardio)), 'Кардио');
  });
  test('лучший результат прошлого раза', () {
    expect(bestText([row(1, w: 40, r: 10), row(2, w: 60, r: 8), row(2, part: 2, w: 40, r: 10)]), '60×8');
    expect(bestText([row(1, s: 30), row(2, s: 45)]), '45 с');
    expect(bestText([row(1, m: 5, k: 71)]), '5 мин · 71 ккал');
    expect(bestText([]), isNull);
  });
  test('даты по-русски', () {
    expect(formatLongDate(DateTime.utc(2026, 11, 17)), 'Вторник, 17 ноября');
    expect(formatShortDate(DateTime.utc(2026, 11, 10)), '10 ноя 2026');
  });
  test('склонение', () {
    expect(plural(1, 'подход', 'подхода', 'подходов'), '1 подход');
    expect(plural(3, 'подход', 'подхода', 'подходов'), '3 подхода');
    expect(plural(11, 'подход', 'подхода', 'подходов'), '11 подходов');
    expect(plural(25, 'подход', 'подхода', 'подходов'), '25 подходов');
  });
}
