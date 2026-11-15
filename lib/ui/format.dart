import '../domain/models.dart';

const _weekdays = [
  'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота',
  'Воскресенье',
];
const _monthsGenitive = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа',
  'сентября', 'октября', 'ноября', 'декабря',
];
const _monthsShort = [
  'янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя',
  'дек',
];
const monthsNominative = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август',
  'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
];

/// «60», «7,5».
String formatNumber(num v) {
  if (v == v.roundToDouble()) return v.round().toString();
  var s = v.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.replaceAll('.', ',');
}

/// «Вторник, 17 ноября».
String formatLongDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_monthsGenitive[d.month - 1]}';

/// «10 ноя 2026».
String formatShortDate(DateTime d) =>
    '${d.day} ${_monthsShort[d.month - 1]} ${d.year}';

/// «1 подход», «3 подхода», «11 подходов».
String plural(int n, String one, String few, String many) {
  final mod10 = n % 10, mod100 = n % 100;
  final word = mod10 == 1 && mod100 != 11
      ? one
      : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14))
          ? few
          : many;
  return '$n $word';
}

String _part(JournalRow r) {
  if (r.weight != null && r.reps != null) {
    return '${formatNumber(r.weight!)}×${r.reps}';
  }
  if (r.reps != null) return '${r.reps}';
  if (r.seconds != null) return '${r.seconds} с';
  return [
    if (r.minutes != null) '${formatNumber(r.minutes!)} мин',
    if (r.kcal != null) '${r.kcal} ккал',
  ].join(' · ');
}

/// «40×10 · 60×10–40×10»: подходы через точку, части дроп-сета через тире.
String formatSets(List<JournalRow> rows) {
  final bySet = <int, List<JournalRow>>{};
  for (final r in rows) {
    bySet.putIfAbsent(r.setNo, () => []).add(r);
  }
  final setNos = bySet.keys.toList()..sort();
  return [
    for (final n in setNos)
      (bySet[n]!..sort((a, b) => a.partNo.compareTo(b.partNo)))
          .map(_part)
          .join('–')
  ].join(' · ');
}

/// Цель упражнения: «4×8–10, дроп-сет».
String targetText(ProgramExercise e) {
  switch (e.type) {
    case ExerciseType.cardio:
      return e.note.isEmpty ? 'Кардио' : e.note;
    case ExerciseType.timed:
      return e.repsTarget.isEmpty
          ? plural(e.sets, 'подход', 'подхода', 'подходов')
          : '${e.sets}×${e.repsTarget} с';
    case ExerciseType.strength:
      final base = e.repsTarget.isEmpty
          ? plural(e.sets, 'подход', 'подхода', 'подходов')
          : '${e.sets}×${e.repsTarget}';
      return e.dropSet ? '$base, дроп-сет' : base;
  }
}

/// Лучший подход тренировки: с наибольшим весом (или временем).
String? bestText(List<JournalRow> rows) {
  if (rows.isEmpty) return null;
  JournalRow best = rows.first;
  for (final r in rows) {
    if ((r.weight ?? -1) > (best.weight ?? -1) ||
        (r.weight == null && best.weight == null &&
            (r.seconds ?? r.reps ?? -1) > (best.seconds ?? best.reps ?? -1))) {
      best = r;
    }
  }
  return _part(best);
}
