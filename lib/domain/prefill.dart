import 'models.dart';

class SetDraft {
  const SetDraft({this.weight, this.reps, this.seconds, this.minutes, this.kcal});
  final double? weight;
  final int? reps;
  final int? seconds;
  final double? minutes;
  final int? kcal;
}

/// Нижняя граница цели: «8–10» → 8, «12» → 12, пусто → 0.
int lowerBound(String target) =>
    int.tryParse(RegExp(r'\d+').firstMatch(target)?.group(0) ?? '') ?? 0;

/// Значения, подставляемые в поля ввода подхода [setNo].
SetDraft prefillSet({
  required ProgramExercise exercise,
  required int setNo,
  required List<JournalRow> today,
  required List<JournalRow> lastSession,
}) {
  JournalRow? find(List<JournalRow> rows, int n) {
    for (final r in rows) {
      if (r.setNo == n && r.partNo == 1) return r;
    }
    return null;
  }

  final source = find(lastSession, setNo) ?? find(today, setNo - 1);
  final target = lowerBound(exercise.repsTarget);
  switch (exercise.type) {
    case ExerciseType.strength:
      return SetDraft(
          weight: source?.weight ?? 0, reps: source?.reps ?? target);
    case ExerciseType.timed:
      return SetDraft(seconds: source?.seconds ?? target);
    case ExerciseType.cardio:
      return SetDraft(
          minutes: source?.minutes ?? 0, kcal: source?.kcal ?? 0);
  }
}
