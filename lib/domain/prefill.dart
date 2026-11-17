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
  // У кардио цель («5 минут») обычно записана в примечании.
  final cardioTarget = target > 0 ? target : lowerBound(exercise.note);

  /// Кардио обычно один подход: берём прошлый результат даже если номер
  /// подхода не совпал, а без истории — цель из программы (мин).
  JournalRow? cardioSource() {
    if (source != null) return source;
    for (final r in [...today.reversed, ...lastSession]) {
      if (r.minutes != null) return r;
    }
    return null;
  }
  switch (exercise.type) {
    case ExerciseType.strength:
      return SetDraft(
          weight: source?.weight ?? 0, reps: source?.reps ?? target);
    case ExerciseType.timed:
      return SetDraft(seconds: source?.seconds ?? target);
    case ExerciseType.cardio:
      final c = cardioSource();
      final minutes = c?.minutes;
      return SetDraft(
          minutes: minutes != null && minutes > 0
              ? minutes
              : cardioTarget.toDouble(),
          kcal: c?.kcal ?? 0);
  }
}
