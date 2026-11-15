enum ExerciseType { strength, timed, cardio }

/// Дата без времени (полночь UTC), чтобы даты сравнивались независимо от пояса.
DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

class ProgramExercise {
  const ProgramExercise({
    required this.workout,
    required this.order,
    required this.name,
    required this.type,
    required this.sets,
    this.repsTarget = '',
    this.dropSet = false,
    this.weightStep = 2.5,
    this.note = '',
  });

  final String workout;
  final int order;
  final String name;
  final ExerciseType type;
  final int sets;
  final String repsTarget;
  final bool dropSet;
  final double weightStep;
  final String note;

  @override
  bool operator ==(Object other) =>
      other is ProgramExercise &&
      other.workout == workout &&
      other.order == order &&
      other.name == name &&
      other.type == type &&
      other.sets == sets &&
      other.repsTarget == repsTarget &&
      other.dropSet == dropSet &&
      other.weightStep == weightStep &&
      other.note == note;

  @override
  int get hashCode => Object.hash(
      workout, order, name, type, sets, repsTarget, dropSet, weightStep, note);

  @override
  String toString() => 'ProgramExercise($workout #$order $name)';
}

class ScheduleEntry {
  const ScheduleEntry({required this.weekday, required this.workout});

  /// [DateTime.monday]..[DateTime.sunday].
  final int weekday;
  final String workout;

  @override
  bool operator ==(Object other) =>
      other is ScheduleEntry &&
      other.weekday == weekday &&
      other.workout == workout;

  @override
  int get hashCode => Object.hash(weekday, workout);

  @override
  String toString() => 'ScheduleEntry($weekday, $workout)';
}

/// Одна часть подхода: у обычного подхода часть одна, у дроп-сета несколько.
class JournalRow {
  const JournalRow({
    required this.id,
    required this.date,
    required this.workout,
    required this.exercise,
    required this.setNo,
    required this.partNo,
    this.weight,
    this.reps,
    this.seconds,
    this.minutes,
    this.kcal,
    this.note = '',
  });

  final String id;
  final DateTime date;
  final String workout;
  final String exercise;
  final int setNo;
  final int partNo;
  final double? weight;
  final int? reps;
  final int? seconds;
  final double? minutes;
  final int? kcal;
  final String note;

  JournalRow copyWith({
    double? weight,
    int? reps,
    int? seconds,
    double? minutes,
    int? kcal,
    String? note,
  }) =>
      JournalRow(
        id: id,
        date: date,
        workout: workout,
        exercise: exercise,
        setNo: setNo,
        partNo: partNo,
        weight: weight ?? this.weight,
        reps: reps ?? this.reps,
        seconds: seconds ?? this.seconds,
        minutes: minutes ?? this.minutes,
        kcal: kcal ?? this.kcal,
        note: note ?? this.note,
      );

  @override
  bool operator ==(Object other) =>
      other is JournalRow &&
      other.id == id &&
      other.date == date &&
      other.workout == workout &&
      other.exercise == exercise &&
      other.setNo == setNo &&
      other.partNo == partNo &&
      other.weight == weight &&
      other.reps == reps &&
      other.seconds == seconds &&
      other.minutes == minutes &&
      other.kcal == kcal &&
      other.note == note;

  @override
  int get hashCode => Object.hash(id, date, workout, exercise, setNo, partNo,
      weight, reps, seconds, minutes, kcal, note);

  @override
  String toString() =>
      'JournalRow($id $date $exercise $setNo.$partNo w=$weight r=$reps s=$seconds m=$minutes k=$kcal "$note")';
}
