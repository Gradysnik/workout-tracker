import '../domain/models.dart';

const programHeader = [
  'Тренировка', 'Порядок', 'Упражнение', 'Тип', 'Подходы', 'Повторы',
  'Дроп-сет', 'Шаг веса', 'Заметка',
];
const scheduleHeader = ['День недели', 'Тренировка'];
const journalHeader = [
  'ID', 'Дата', 'Тренировка', 'Упражнение', 'Подход', 'Часть', 'Вес',
  'Повторы', 'Секунды', 'Минуты', 'Ккал', 'Заметка',
];

const programSheet = 'Программа';
const scheduleSheet = 'Расписание';
const journalSheet = 'Журнал';

const defaultWeightStep = 2.5;

const _typeNames = {
  'силовое': ExerciseType.strength,
  'время': ExerciseType.timed,
  'кардио': ExerciseType.cardio,
};
const _weekdayShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const _weekdayFull = [
  'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота',
  'воскресенье',
];

String typeName(ExerciseType type) =>
    _typeNames.entries.firstWhere((e) => e.value == type).key;

String weekdayName(int weekday) => _weekdayShort[weekday - 1];

class ParseResult<T> {
  ParseResult(this.items, this.errors);
  final List<T> items;
  final List<String> errors;
}

String _text(List<Object?> row, int i) {
  if (i >= row.length || row[i] == null) return '';
  final v = row[i];
  if (v is double && v == v.roundToDouble()) return v.toInt().toString();
  return v.toString().trim();
}

/// Число из ячейки: число, строка с точкой или запятой. Пусто → null.
/// Непонятное значение бросает [FormatException].
double? _number(List<Object?> row, int i) {
  if (i >= row.length || row[i] == null) return null;
  final v = row[i];
  if (v is num) return v.toDouble();
  final s = v.toString().trim().replaceAll(',', '.').replaceAll(' ', '');
  if (s.isEmpty) return null;
  return double.parse(s);
}

bool _isBlank(List<Object?> row) =>
    row.every((c) => c == null || c.toString().trim().isEmpty);

DateTime? _date(Object? cell) {
  if (cell is num) {
    // Порядковый номер даты Google Sheets: дни от 30.12.1899.
    return DateTime.utc(1899, 12, 30).add(Duration(days: cell.floor()));
  }
  final s = cell?.toString().trim() ?? '';
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (iso != null) {
    return DateTime.utc(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  }
  final ru = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(s);
  if (ru != null) {
    return DateTime.utc(int.parse(ru[3]!), int.parse(ru[2]!), int.parse(ru[1]!));
  }
  return null;
}

String formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Обходит строки данных (без заголовка), пропуская пустые.
/// [parse] возвращает элемент или бросает [FormatException] с текстом ошибки.
ParseResult<T> _parse<T>(
    String sheet, List<List<Object?>> rows, T Function(List<Object?> row) parse) {
  final items = <T>[];
  final errors = <String>[];
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (_isBlank(row)) continue;
    try {
      items.add(parse(row));
    } on FormatException catch (e) {
      errors.add('$sheet, строка ${i + 1}: ${e.message}');
    }
  }
  return ParseResult(items, errors);
}

double? _numberIn(List<Object?> row, int i, String column) {
  try {
    return _number(row, i);
  } on FormatException {
    throw FormatException(
        'в колонке «$column» должно быть число, а там «${_text(row, i)}»');
  }
}

ParseResult<ProgramExercise> parseProgram(List<List<Object?>> rows) =>
    _parse(programSheet, rows, (row) {
      final workout = _text(row, 0);
      final name = _text(row, 2);
      if (name.isEmpty) throw const FormatException('пустое название упражнения');
      if (workout.isEmpty) throw const FormatException('пустое название тренировки');
      final typeText = _text(row, 3);
      final type = _typeNames[typeText.toLowerCase()];
      if (type == null) {
        throw FormatException(
            'неизвестный тип «$typeText» (нужно: силовое, время или кардио)');
      }
      return ProgramExercise(
        workout: workout,
        order: _numberIn(row, 1, 'Порядок')?.round() ?? 0,
        name: name,
        type: type,
        sets: _numberIn(row, 4, 'Подходы')?.round() ?? 1,
        repsTarget: _text(row, 5),
        dropSet: _text(row, 6).toLowerCase() == 'да',
        weightStep: _numberIn(row, 7, 'Шаг веса') ?? defaultWeightStep,
        note: _text(row, 8),
      );
    });

ParseResult<ScheduleEntry> parseSchedule(List<List<Object?>> rows) =>
    _parse(scheduleSheet, rows, (row) {
      final day = _text(row, 0);
      final key = day.toLowerCase().replaceAll('.', '');
      var index = _weekdayShort.indexWhere((d) => d.toLowerCase() == key);
      if (index < 0) index = _weekdayFull.indexOf(key);
      if (index < 0) throw FormatException('непонятный день недели «$day»');
      final workout = _text(row, 1);
      if (workout.isEmpty) throw const FormatException('пустое название тренировки');
      return ScheduleEntry(weekday: index + 1, workout: workout);
    });

ParseResult<JournalRow> parseJournal(List<List<Object?>> rows) =>
    _parse(journalSheet, rows, (row) {
      final id = _text(row, 0);
      if (id.isEmpty) throw const FormatException('пустой ID');
      final date = _date(row.length > 1 ? row[1] : null);
      if (date == null) {
        throw FormatException('непонятная дата «${_text(row, 1)}»');
      }
      return JournalRow(
        id: id,
        date: date,
        workout: _text(row, 2),
        exercise: _text(row, 3),
        setNo: _numberIn(row, 4, 'Подход')?.round() ?? 1,
        partNo: _numberIn(row, 5, 'Часть')?.round() ?? 1,
        weight: _numberIn(row, 6, 'Вес'),
        reps: _numberIn(row, 7, 'Повторы')?.round(),
        seconds: _numberIn(row, 8, 'Секунды')?.round(),
        minutes: _numberIn(row, 9, 'Минуты'),
        kcal: _numberIn(row, 10, 'Ккал')?.round(),
        note: _text(row, 11),
      );
    });

Object _numCell(num? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.toInt() : v;
}

List<Object?> journalRowToCells(JournalRow r) => [
      r.id,
      formatDate(r.date),
      r.workout,
      r.exercise,
      r.setNo,
      r.partNo,
      _numCell(r.weight),
      _numCell(r.reps),
      _numCell(r.seconds),
      _numCell(r.minutes),
      _numCell(r.kcal),
      r.note,
    ];

List<Object?> programToCells(ProgramExercise e) => [
      e.workout,
      e.order,
      e.name,
      typeName(e.type),
      e.sets,
      e.repsTarget,
      e.dropSet ? 'да' : 'нет',
      e.weightStep == defaultWeightStep ? '' : _numCell(e.weightStep),
      e.note,
    ];

List<Object?> scheduleToCells(ScheduleEntry e) =>
    [weekdayName(e.weekday), e.workout];
