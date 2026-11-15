import 'exercise_key.dart';
import 'models.dart';

class TodayChoice {
  const TodayChoice(
      {required this.workout, this.missedWorkout, this.early = false});

  /// Тренировка, которую показывает экран «Сегодня».
  final String workout;

  /// Пропущенная тренировка, о которой стоит напомнить.
  final String? missedWorkout;

  /// Тренировка стоит в расписании на более поздний день.
  final bool early;
}

typedef Session = ({DateTime date, String workout});
typedef _Slot = ({DateTime date, String workout});

TodayChoice? chooseWorkout({
  required DateTime today,
  required List<ScheduleEntry> schedule,
  required List<Session> sessions,
}) {
  if (schedule.isEmpty) return null;
  today = dateOnly(today);
  final done = [
    for (final s in sessions)
      (date: dateOnly(s.date), workout: exerciseKey(s.workout))
  ];

  for (final s in sessions.reversed) {
    if (dateOnly(s.date) == today) return TodayChoice(workout: s.workout);
  }

  final byWeekday = <int, String>{};
  for (final e in schedule) {
    byWeekday.putIfAbsent(e.weekday, () => e.workout);
  }
  // Слоты расписания: три недели назад и две вперёд.
  final slots = <_Slot>[];
  for (var offset = -21; offset <= 14; offset++) {
    final date = today.add(Duration(days: offset));
    final workout = byWeekday[date.weekday];
    if (workout != null) slots.add((date: date, workout: workout));
  }

  bool closed(int i) {
    final key = exerciseKey(slots[i].workout);
    final from = i == 0 ? null : slots[i - 1].date;
    return done.any((s) =>
        s.workout == key &&
        (from == null || s.date.isAfter(from)) &&
        !s.date.isAfter(today));
  }

  final todayIdx = slots.indexWhere((s) => s.date == today);
  final prevIdx = slots.lastIndexWhere((s) => s.date.isBefore(today));
  String? missed;
  if (prevIdx >= 1 && !closed(prevIdx) && closed(prevIdx - 1)) {
    missed = slots[prevIdx].workout;
  }

  if (todayIdx >= 0 && !closed(todayIdx)) {
    return TodayChoice(workout: slots[todayIdx].workout, missedWorkout: missed);
  }
  if (missed != null) return TodayChoice(workout: missed);
  for (var i = prevIdx + 1; i < slots.length; i++) {
    if (!closed(i)) {
      return TodayChoice(
          workout: slots[i].workout, early: slots[i].date.isAfter(today));
    }
  }
  return TodayChoice(workout: slots[prevIdx + 1].workout);
}
