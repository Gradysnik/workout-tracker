import 'dart:math' as math;

import 'models.dart';

enum Metric { maxWeight, volume, reps, seconds, kcal }

typedef ProgressPoint = ({DateTime date, double value});

List<Metric> metricsFor(ExerciseType type) => switch (type) {
      ExerciseType.strength => const [Metric.maxWeight, Metric.volume, Metric.reps],
      ExerciseType.timed => const [Metric.seconds],
      ExerciseType.cardio => const [Metric.kcal],
    };

/// Одна точка на дату тренировки, по возрастанию дат.
List<ProgressPoint> progressSeries(List<JournalRow> rows, Metric metric) {
  final byDate = <DateTime, double>{};
  for (final r in rows) {
    final double? v = switch (metric) {
      Metric.maxWeight => r.weight,
      Metric.volume =>
        r.weight == null || r.reps == null ? null : r.weight! * r.reps!,
      Metric.reps => r.reps?.toDouble(),
      Metric.seconds => r.seconds?.toDouble(),
      Metric.kcal => r.kcal?.toDouble(),
    };
    if (v == null) continue;
    final date = dateOnly(r.date);
    final isMax = metric == Metric.maxWeight || metric == Metric.seconds;
    byDate.update(date, (old) => isMax ? math.max(old, v) : old + v,
        ifAbsent: () => v);
  }
  final dates = byDate.keys.toList()..sort();
  return [for (final d in dates) (date: d, value: byDate[d]!)];
}
