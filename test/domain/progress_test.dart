import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/domain/models.dart';
import 'package:workout_tracker/domain/progress.dart';

JournalRow row(int day, int setNo, {int part = 1, double? w, int? r, int? s, int? k}) =>
    JournalRow(id: '$day-$setNo-$part', date: DateTime.utc(2026, 11, day), workout: 'A',
        exercise: 'Тяга', setNo: setNo, partNo: part, weight: w, reps: r, seconds: s, kcal: k);

void main() {
  final rows = [
    row(10, 1, w: 40, r: 10), row(10, 2, w: 60, r: 8), row(10, 2, part: 2, w: 40, r: 10),
    row(3, 1, w: 40, r: 10), row(3, 2, w: 50, r: 10),
  ];
  test('одна точка на дату, по возрастанию дат', () {
    final s = progressSeries(rows, Metric.maxWeight);
    expect(s.map((p) => p.date.day), [3, 10]);
    expect(s.map((p) => p.value), [50, 60]);
  });
  test('объём — сумма вес×повторы по всем частям', () {
    expect(progressSeries(rows, Metric.volume).last.value, 40 * 10 + 60 * 8 + 40 * 10);
  });
  test('повторы — сумма', () {
    expect(progressSeries(rows, Metric.reps).last.value, 28);
  });
  test('секунды — максимум, ккал — сумма, строки без значения пропускаются', () {
    final t = [row(10, 1, s: 30), row(10, 2, s: 45), row(10, 3, w: 5, r: 5)];
    expect(progressSeries(t, Metric.seconds).single.value, 45);
    expect(progressSeries([row(10, 1, k: 50), row(10, 2, k: 21)], Metric.kcal).single.value, 71);
    expect(progressSeries(t, Metric.kcal), isEmpty);
  });
  test('набор метрик зависит от типа', () {
    expect(metricsFor(ExerciseType.strength), [Metric.maxWeight, Metric.volume, Metric.reps]);
    expect(metricsFor(ExerciseType.timed), [Metric.seconds]);
    expect(metricsFor(ExerciseType.cardio), [Metric.kcal]);
  });
}
