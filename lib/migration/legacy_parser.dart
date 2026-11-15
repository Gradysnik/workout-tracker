import '../domain/models.dart';

/// Разбор старой таблицы «строки — упражнения, колонки — недели».
class LegacyResult {
  final program = <ProgramExercise>[];
  final schedule = <ScheduleEntry>[];
  final journal = <JournalRow>[];
  final warnings = <String>[];
}

const _weekdays = {
  'ПН': DateTime.monday, 'ВТ': DateTime.tuesday, 'СР': DateTime.wednesday,
  'ЧТ': DateTime.thursday, 'ПТ': DateTime.friday, 'СБ': DateTime.saturday,
  'ВС': DateTime.sunday,
};
const _workoutNames = {
  'Сп+Биц': 'Спина + Бицепс',
  'Гр+Триц': 'Грудь + Трицепс',
  'Ноги+Кор': 'Ноги + Кор',
};

final _section = RegExp(r'^(ПН|ВТ|СР|ЧТ|ПТ|СБ|ВС)\.\s*(.+)$');
final _target = RegExp(r'^(\d+)\s*[×xхXХ]\s*(\d+(?:\s*[–-]\s*\d+)?)(.*)$');
final _timedTarget = RegExp(r'(\d+)\s*по\s*(\d+\s*[–-]\s*\d+)');
final _kcal = RegExp(r'(\d+)\s*[кk]');
final _minutes = RegExp(r'(\d+)\s*m');
final _part = RegExp(r'^(\d+(?:,\d+)?)\.(\d+)$');
final _date = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$');

String _stripParens(String s) =>
    s.trim().replaceAll(RegExp(r'^\(|\)$'), '').trim();

String _dash(String s) => s.replaceAll(RegExp(r'\s*-\s*'), '–').replaceAll(' ', '');
String _joined(Iterable<String> lines) =>
    lines.map((l) => l.trim()).where((l) => l.isNotEmpty).join(' ');

List<DateTime> _headerDates(String cell) {
  final dates = <DateTime>[];
  for (final line in cell.split('\n')) {
    final m = _date.firstMatch(line.trim());
    if (m == null) return const [];
    dates.add(DateTime.utc(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!)));
  }
  return dates.length == 3 ? dates : const [];
}

ProgramExercise _exercise(
    String workout, int order, List<String> row) {
  final lines = row[0].split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final target = _target.firstMatch(lines.last);
  if (target != null && lines.length > 1) {
    final rest = target[3]!;
    final dropSet = rest.toLowerCase().contains('дроп');
    final note = dropSet ? '' : rest.replaceAll(RegExp(r'^[\s,.]+|[\s.]+$'), '');
    return ProgramExercise(
        workout: workout, order: order,
        name: _joined(lines.take(lines.length - 1)),
        type: ExerciseType.strength, sets: int.parse(target[1]!),
        repsTarget: _dash(target[2]!), dropSet: dropSet, note: note);
  }
  if (row[0].contains('секунд')) {
    final t = _timedTarget.firstMatch(row[0]);
    return ProgramExercise(
        workout: workout, order: order,
        name: _joined(lines.where((l) => !l.contains('секунд'))),
        type: ExerciseType.timed,
        sets: t == null ? 3 : int.parse(t[1]!),
        repsTarget: t == null ? '' : _dash(t[2]!));
  }
  if (row.skip(1).any(_kcal.hasMatch)) {
    final all = _joined(lines);
    final digit = all.indexOf(RegExp(r'\d'));
    var name = digit > 0 ? all.substring(0, digit).trim() : lines.first;
    name = name[0].toUpperCase() + name.substring(1);
    return ProgramExercise(
        workout: workout, order: order, name: name,
        type: ExerciseType.cardio, sets: 1,
        note: digit > 0 ? all.substring(digit) : _joined(lines.skip(1)));
  }
  return ProgramExercise(
      workout: workout, order: order, name: _joined(lines),
      type: ExerciseType.strength, sets: 3);
}

typedef _Part = ({int setNo, int partNo, double? weight, int? reps, int? seconds,
    double? minutes, int? kcal, String note});

_Part _p(int setNo, int partNo,
        {double? weight, int? reps, int? seconds, double? minutes, int? kcal, String note = ''}) =>
    (setNo: setNo, partNo: partNo, weight: weight, reps: reps, seconds: seconds,
        minutes: minutes, kcal: kcal, note: note);

/// Части подходов из ячейки или null, если ячейку не удалось разобрать.
List<_Part>? _cell(ExerciseType type, String text) {
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  switch (type) {
    case ExerciseType.cardio:
      final kcal = int.tryParse(_kcal.firstMatch(text)?.group(1) ?? '');
      final minutes = double.tryParse(_minutes.firstMatch(text)?.group(1) ?? '');
      if (kcal == null && minutes == null) return null;
      if ((kcal ?? 0) == 0 && (minutes ?? 0) == 0) return const [];
      final note = text
          .replaceAll(_kcal, '')
          .replaceAll(_minutes, '')
          .replaceAll(RegExp(r'[-\n]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return [_p(1, 1, minutes: minutes, kcal: kcal, note: note)];
    case ExerciseType.timed:
      final out = <_Part>[];
      final values = lines.expand((l) => l.split('.')).toList();
      for (var i = 0; i < values.length; i++) {
        final s = int.tryParse(values[i].trim());
        if (s == null) return null;
        if (s > 0) out.add(_p(i + 1, 1, seconds: s));
      }
      return out;
    case ExerciseType.strength:
      final triple = lines.length == 1
          ? RegExp(r'^(\d+\.\d+\.\d+)(\s.*)?$').firstMatch(lines[0])
          : null;
      if (triple != null) {
        final reps = triple[1]!.split('.').map(int.parse).toList();
        final note = _stripParens(triple[2] ?? '');
        return [
          for (var i = 0; i < reps.length; i++)
            if (reps[i] > 0) _p(i + 1, 1, reps: reps[i], note: i == 0 ? note : '')
        ];
      }
      final out = <_Part>[];
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var note = '';
        final space = line.indexOf(RegExp(r'\s'));
        if (space > 0) {
          note = _stripParens(line.substring(space));
          line = line.substring(0, space);
        }
        var partNo = 0;
        for (final piece in line.split('-')) {
          final m = _part.firstMatch(piece.trim());
          if (m == null) return null;
          final weight = double.parse(m[1]!.replaceAll(',', '.'));
          final reps = int.parse(m[2]!);
          if (weight == 0 && reps == 0) continue;
          partNo++;
          out.add(_p(i + 1, partNo,
              weight: weight, reps: reps, note: partNo == 1 ? note : ''));
        }
      }
      return out;
  }
}

LegacyResult parseLegacy(List<List<String>> cells) {
  final result = LegacyResult();
  if (cells.isEmpty) return result;
  final header = cells.first;
  final dates = [for (final c in header) _headerDates(c)];

  var section = -1;
  var workout = '';
  var order = 0;
  for (var r = 1; r < cells.length; r++) {
    final row = cells[r];
    if (row.isEmpty || row[0].trim().isEmpty) continue;
    final sec = _section.firstMatch(row[0].trim());
    if (sec != null) {
      section++;
      order = 0;
      final short = sec[2]!.trim();
      workout = _workoutNames[short] ?? short;
      result.schedule
          .add(ScheduleEntry(weekday: _weekdays[sec[1]]!, workout: workout));
      continue;
    }
    if (section < 0) continue;
    order++;
    final exercise = _exercise(workout, order, row);
    result.program.add(exercise);
    for (var c = 1; c < row.length && c < dates.length; c++) {
      final text = row[c].trim();
      if (text.isEmpty || text.toLowerCase() == 'skip' || section >= dates[c].length) {
        continue;
      }
      final parts = _cell(exercise.type, text);
      if (parts == null) {
        result.warnings.add('R${r + 1}C${c + 1}: $text');
        continue;
      }
      for (final p in parts) {
        result.journal.add(JournalRow(
          id: 'm-${r + 1}-${c + 1}-${p.setNo}-${p.partNo}',
          date: dates[c][section],
          workout: workout,
          exercise: exercise.name,
          setNo: p.setNo,
          partNo: p.partNo,
          weight: p.weight,
          reps: p.reps,
          seconds: p.seconds,
          minutes: p.minutes,
          kcal: p.kcal,
          note: p.note,
        ));
      }
    }
  }
  return result;
}
