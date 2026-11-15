import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/domain/models.dart';
import 'package:workout_tracker/sheets/sheet_codec.dart';

void main() {
  final drop = JournalRow(id: 'a1', date: DateTime.utc(2026, 11, 10), workout: 'Спина + Бицепс',
      exercise: 'Тяга', setNo: 4, partNo: 2, weight: 40, reps: 10, note: 'у стены');
  final cardio = JournalRow(id: 'a2', date: DateTime.utc(2026, 11, 10), workout: 'Спина + Бицепс',
      exercise: 'Гребной тренажёр', setNo: 1, partNo: 1, minutes: 5, kcal: 71);

  group('журнал', () {
    test('заголовки точно как в спецификации', () {
      expect(journalHeader, ['ID', 'Дата', 'Тренировка', 'Упражнение', 'Подход', 'Часть',
        'Вес', 'Повторы', 'Секунды', 'Минуты', 'Ккал', 'Заметка']);
      expect(programHeader, ['Тренировка', 'Порядок', 'Упражнение', 'Тип', 'Подходы',
        'Повторы', 'Дроп-сет', 'Шаг веса', 'Заметка']);
      expect(scheduleHeader, ['День недели', 'Тренировка']);
    });
    test('запись и чтение дают ту же строку', () {
      for (final r in [drop, cardio]) {
        final cells = journalRowToCells(r);
        expect(cells, hasLength(12));
        expect(parseJournal([journalHeader, cells]).items.single, r);
      }
    });
    test('дата записывается строкой yyyy-MM-dd', () {
      expect(journalRowToCells(drop)[1], '2026-11-10');
    });
    test('дата dd.MM.yyyy и порядковый номер Sheets читаются как та же дата', () {
      for (final date in ['10.11.2026', '2026-11-10', 46336]) {
        final r = parseJournal([journalHeader, ['x', date, 'W', 'E', 1, 1, 60, 10]]);
        expect(r.errors, isEmpty);
        expect(r.items.single.date, DateTime.utc(2026, 11, 10));
      }
    });
    test('числа строкой, с запятой, дробные и целые', () {
      for (final (cell, value) in [('7,5', 7.5), ('7.5', 7.5), (7.5, 7.5), (60, 60.0), ('60', 60.0)]) {
        final r = parseJournal([journalHeader, ['x', '2026-11-10', 'W', 'E', '1', 1.0, cell, '10']]);
        expect(r.items.single.weight, value);
        expect(r.items.single.reps, 10);
        expect(r.items.single.setNo, 1);
      }
    });
    test('короткая строка без хвостовых пустых ячеек', () {
      final r = parseJournal([journalHeader, ['x', '2026-11-10', 'W', 'E', 1, 1, 60, 10]]);
      expect(r.items.single.note, '');
      expect(r.items.single.kcal, isNull);
    });
    test('пустой ID или неразборная дата — строка пропущена с ошибкой', () {
      final r = parseJournal([journalHeader,
        ['', '2026-11-10', 'W', 'E', 1, 1, 60, 10],
        ['y', 'вчера', 'W', 'E', 1, 1, 60, 10],
        ['z', '2026-11-10', 'W', 'E', 1, 1, 60, 10]]);
      expect(r.items.map((e) => e.id), ['z']);
      expect(r.errors, ['Журнал, строка 2: пустой ID', 'Журнал, строка 3: непонятная дата «вчера»']);
    });
    test('полностью пустые строки пропускаются без ошибок', () {
      final r = parseJournal([journalHeader, [], ['', '', ''], ['z', '2026-11-10', 'W', 'E', 1, 1]]);
      expect(r.items, hasLength(1));
      expect(r.errors, isEmpty);
    });
  });

  group('программа', () {
    test('обычная строка', () {
      final r = parseProgram([programHeader,
        ['Спина + Бицепс', 2, 'Тяга верхнего блока', 'Силовое ', 4, '8–10', 'Да', 5, 'широкий']]);
      expect(r.errors, isEmpty);
      expect(r.items.single, const ProgramExercise(workout: 'Спина + Бицепс', order: 2,
          name: 'Тяга верхнего блока', type: ExerciseType.strength, sets: 4,
          repsTarget: '8–10', dropSet: true, weightStep: 5, note: 'широкий'));
    });
    test('значения по умолчанию: шаг 2,5, дроп-сет нет, подходы у кардио 1', () {
      final r = parseProgram([programHeader,
        ['A', 1, 'Гребля', 'кардио'], ['A', 2, 'Планка', 'время', 3, '30–45', 'нет']]);
      expect(r.errors, isEmpty);
      expect((r.items[0].sets, r.items[0].weightStep, r.items[0].dropSet), (1, 2.5, false));
      expect(r.items[1].type, ExerciseType.timed);
    });
    test('числовая цель повторов читается как текст', () {
      expect(parseProgram([programHeader, ['A', 1, 'Сгибания', 'силовое', 3, 12]]).items.single.repsTarget, '12');
    });
    test('ошибочные строки пропускаются с сообщением, остальные загружаются', () {
      final r = parseProgram([programHeader,
        ['A', 1, 'Хорошее', 'силовое', 3, '10'],
        ['A', 2, 'Плохой тип', 'йога', 3, '10'],
        ['A', 3, '', 'силовое', 3, '10'],
        ['A', 4, 'Плохие подходы', 'силовое', 'много', '10'],
        [],
        ['', 5, 'Без тренировки', 'силовое', 3, '10'],
        ['A', 6, 'Тоже хорошее', 'силовое', 3, '10']]);
      expect(r.items.map((e) => e.name), ['Хорошее', 'Тоже хорошее']);
      expect(r.errors, [
        'Программа, строка 3: неизвестный тип «йога» (нужно: силовое, время или кардио)',
        'Программа, строка 4: пустое название упражнения',
        'Программа, строка 5: в колонке «Подходы» должно быть число, а там «много»',
        'Программа, строка 7: пустое название тренировки',
      ]);
    });
    test('шаг веса по умолчанию записывается пустой ячейкой', () {
      const e = ProgramExercise(workout: 'A', order: 1, name: 'Тяга', type: ExerciseType.strength, sets: 4);
      expect(programToCells(e)[7], '');
      expect(parseProgram([programHeader, programToCells(e)]).items.single, e);
    });
    test('только заголовок или пустой лист', () {
      expect(parseProgram([programHeader]).items, isEmpty);
      expect(parseProgram([]).items, isEmpty);
    });
    test('запись и чтение дают то же упражнение', () {
      const e = ProgramExercise(workout: 'A', order: 1, name: 'Тяга', type: ExerciseType.strength,
          sets: 4, repsTarget: '8–10', dropSet: true, weightStep: 5, note: 'n');
      expect(parseProgram([programHeader, programToCells(e)]).items.single, e);
    });
  });

  group('расписание', () {
    test('короткие и полные названия дней в любом регистре', () {
      final r = parseSchedule([scheduleHeader, ['Вт', 'A'], ['четверг', 'B'], ['СБ', 'C'], ['Вс.', 'D']]);
      expect(r.errors, isEmpty);
      expect(r.items.map((e) => e.weekday),
          [DateTime.tuesday, DateTime.thursday, DateTime.saturday, DateTime.sunday]);
    });
    test('неизвестный день — ошибка', () {
      final r = parseSchedule([scheduleHeader, ['завтра', 'A'], ['Пн', 'B']]);
      expect(r.items.single.workout, 'B');
      expect(r.errors, ['Расписание, строка 2: непонятный день недели «завтра»']);
    });
    test('запись и чтение', () {
      const e = ScheduleEntry(weekday: DateTime.saturday, workout: 'Ноги + Кор');
      expect(scheduleToCells(e), ['Сб', 'Ноги + Кор']);
      expect(parseSchedule([scheduleHeader, scheduleToCells(e)]).items.single, e);
    });
  });
}
