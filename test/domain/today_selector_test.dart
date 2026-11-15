import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/domain/models.dart';
import 'package:workout_tracker/domain/today_selector.dart';

DateTime d(int day) => DateTime.utc(2026, 11, day);
typedef S = ({DateTime date, String workout});

const schedule = [
  ScheduleEntry(weekday: DateTime.tuesday, workout: 'A'),
  ScheduleEntry(weekday: DateTime.thursday, workout: 'B'),
  ScheduleEntry(weekday: DateTime.saturday, workout: 'C'),
];
final List<S> week1 = [
  (date: d(10), workout: 'A'),
  (date: d(12), workout: 'B'),
  (date: d(14), workout: 'C'),
];

TodayChoice? pick(int day, [List<S> extra = const []]) => chooseWorkout(
    today: d(day), schedule: schedule, sessions: [...week1, ...extra]);

void main() {
  test('в день по расписанию — тренировка этого дня', () {
    final c = pick(17)!;
    expect((c.workout, c.missedWorkout, c.early), ('A', null, false));
  });
  test('на следующий день после пропуска — пропущенная', () {
    final c = pick(18)!;
    expect((c.workout, c.missedWorkout, c.early), ('A', null, false));
  });
  test('в следующий день по расписанию — его тренировка и напоминание о пропущенной', () {
    final c = pick(19)!;
    expect((c.workout, c.missedWorkout, c.early), ('B', 'A', false));
  });
  test('пропущенная, сделанная позже, не напоминается', () {
    final c = pick(19, [(date: d(18), workout: 'A')])!;
    expect((c.workout, c.missedWorkout), ('B', null));
  });
  test('в день без тренировки — ближайшая следующая, досрочно', () {
    final c = pick(16)!;
    expect((c.workout, c.missedWorkout, c.early), ('A', null, true));
  });
  test('сделанная досрочно не предлагается повторно', () {
    final c = pick(17, [(date: d(16), workout: 'A')])!;
    expect((c.workout, c.early), ('B', true));
  });
  test('сделанная сегодня остаётся на экране', () {
    final c = pick(17, [(date: d(17), workout: 'A')])!;
    expect((c.workout, c.early), ('A', false));
  });
  test('после недели пропусков долги не копятся', () {
    final c = pick(24)!;
    expect((c.workout, c.missedWorkout), ('A', null));
  });
  test('пропущенная, сделанная сегодня, остаётся на экране', () {
    final c = pick(18, [(date: d(18), workout: 'A')])!;
    expect((c.workout, c.missedWorkout, c.early), ('A', null, false));
  });
  test('пустое расписание — null', () {
    expect(chooseWorkout(today: d(17), schedule: const [], sessions: week1), isNull);
  });
  test('без единой записи в журнале — тренировка по расписанию без напоминаний', () {
    final c = chooseWorkout(today: d(19), schedule: schedule, sessions: const [])!;
    expect((c.workout, c.missedWorkout), ('B', null));
  });
}
