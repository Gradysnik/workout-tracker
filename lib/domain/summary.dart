import 'models.dart';

/// Сравнение одного упражнения с прошлой тренировкой.
class ExerciseResult {
  const ExerciseResult({
    required this.exercise,
    required this.value,
    required this.previous,
    required this.unit,
  });

  final ProgramExercise exercise;

  /// Главный показатель сегодня и в прошлый раз (null — прошлого раза нет).
  final double value;
  final double? previous;

  /// «кг» (объём), «с», «мин».
  final String unit;

  double? get delta => previous == null ? null : value - previous!;

  /// Изменение в процентах; null, если прошлого раза нет или он нулевой.
  double? get percent =>
      previous == null || previous == 0 ? null : (value - previous!) / previous! * 100;
}

class WorkoutSummary {
  const WorkoutSummary(this.results);

  /// Только упражнения, по которым сегодня есть подходы.
  final List<ExerciseResult> results;

  int get improved => results.where((r) => (r.delta ?? 0) > 0).length;
  int get compared => results.where((r) => r.delta != null).length;
}

double _volume(List<JournalRow> rows) => rows.fold(
    0.0, (sum, r) => sum + (r.weight ?? 0) * (r.reps ?? 0));

double _best(List<JournalRow> rows, num? Function(JournalRow) pick) =>
    rows.fold(0.0, (m, r) => (pick(r) ?? 0) > m ? pick(r)!.toDouble() : m);

double _sum(List<JournalRow> rows, num? Function(JournalRow) pick) =>
    rows.fold(0.0, (s, r) => s + (pick(r) ?? 0));

/// Итог тренировки: для силовых — объём (вес × повторы), для упражнений
/// на время — лучший подход, для кардио — минуты.
WorkoutSummary summarize(
    List<({ProgramExercise exercise, List<JournalRow> today, List<JournalRow> last})>
        items) {
  final results = <ExerciseResult>[];
  for (final i in items) {
    if (i.today.isEmpty) continue;
    final (double Function(List<JournalRow>) measure, String unit) =
        switch (i.exercise.type) {
      ExerciseType.strength => (_volume, 'кг'),
      ExerciseType.timed => ((r) => _best(r, (x) => x.seconds), 'с'),
      ExerciseType.cardio => ((r) => _sum(r, (x) => x.minutes), 'мин'),
    };
    results.add(ExerciseResult(
      exercise: i.exercise,
      value: measure(i.today),
      previous: i.last.isEmpty ? null : measure(i.last),
      unit: unit,
    ));
  }
  return WorkoutSummary(results);
}
