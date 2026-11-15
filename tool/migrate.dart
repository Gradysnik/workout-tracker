// Перенос истории из старой таблицы.
// Запуск: dart run tool/migrate.dart <выгрузка.csv> <каталог для результата>
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:workout_tracker/migration/legacy_parser.dart';
import 'package:workout_tracker/sheets/sheet_codec.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Использование: dart run tool/migrate.dart <input.csv> <outDir>');
    exit(64);
  }
  final input = File(args[0]).readAsStringSync();
  final cells = [
    for (final row in Csv().decode(input))
      [for (final c in row) c.toString().replaceAll('\r\n', '\n')]
  ];
  final result = parseLegacy(cells);

  final out = Directory(args[1])..createSync(recursive: true);
  void write(String name, List<String> header, Iterable<List<Object?>> rows) {
    File('${out.path}/$name')
        .writeAsStringSync(Csv(lineDelimiter: '\n').encode([header, ...rows]));
  }

  write('program.csv', programHeader, result.program.map(programToCells));
  write('schedule.csv', scheduleHeader, result.schedule.map(scheduleToCells));
  write('journal.csv', journalHeader, result.journal.map(journalRowToCells));

  stdout.writeln('Упражнений: ${result.program.length}, '
      'дней в расписании: ${result.schedule.length}, '
      'строк журнала: ${result.journal.length}');
  for (final w in result.warnings) {
    stdout.writeln('Не разобрано: $w');
  }
}
