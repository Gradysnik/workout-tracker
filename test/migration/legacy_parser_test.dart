import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/domain/models.dart';
import 'package:workout_tracker/migration/legacy_parser.dart';
import 'package:workout_tracker/sheets/sheet_codec.dart';

// Уменьшенная копия настоящей таблицы: две недели и служебная колонка.
const sample = [
  ['Упражнение', '09.09.2025\n11.09.2025\n13.09.2025', '06.11.2026\n04.11.2026\n08.11.2026', 'Столбец 26'],
  ['ВТ. Сп+Биц'],
  ['Гребной тренажёр \n5 минут.', '', '64к', '0k'],
  ['Тяга верхнего блока \nк груди (широкий)\n4×8–10', '35.10\n45.8\n40.9\n40.9-30.8-20.10', '40.10\n55.10\n55.10\n60.10', '0.0\n0.0\n0.0\n0.0'],
  ['Сгибания рук на \nнижнем блоке (канат)\n3×12, дроп-сет', '17.12\n17.6\n12.10-7.10-5.10', '15.12 (у стены)\n15.12\n15.12', '0.0\n0.0\n0.0-0.0'],
  ['ЧТ. Гр+Триц'],
  ['Планка с подъёмом ног\n3 по 30–45 секунд.', '30.30.30', '40.40.40', '0.0.0'],
  ['Жим гантелей лёжа\n4×8–10', 'сорок', '7,5.10', ''],
  ['СБ. Ноги+Кор'],
  ['Ходьба на дорожке \n5–7%, 5–7 минут.', '7%-5.5s\n7m-57k', '10%-5.5s\n7m-80k', '0%-0.0s\n0m-0k'],
  ['Свободна программа\nна пресс х20', '10.21\n10.21\n10.15', '20.20.20', '0.0\n0.0\n0.0'],
];

void main() {
  final r = parseLegacy(sample);
  ProgramExercise ex(String name) => r.program.firstWhere((e) => e.name == name);
  List<JournalRow> rows(String name, int y, int m, int d) => r.journal
      .where((j) => j.exercise == name && j.date == DateTime.utc(y, m, d))
      .toList();

  test('расписание и названия тренировок', () {
    expect(r.schedule, const [
      ScheduleEntry(weekday: DateTime.tuesday, workout: 'Спина + Бицепс'),
      ScheduleEntry(weekday: DateTime.thursday, workout: 'Грудь + Трицепс'),
      ScheduleEntry(weekday: DateTime.saturday, workout: 'Ноги + Кор'),
    ]);
  });
  test('программа: названия, типы, цели, порядок', () {
    expect(r.program.map((e) => e.name), [
      'Гребной тренажёр', 'Тяга верхнего блока к груди (широкий)',
      'Сгибания рук на нижнем блоке (канат)', 'Планка с подъёмом ног',
      'Жим гантелей лёжа', 'Ходьба на дорожке', 'Свободна программа на пресс х20',
    ]);
    final pull = ex('Тяга верхнего блока к груди (широкий)');
    expect((pull.type, pull.sets, pull.repsTarget, pull.dropSet, pull.order, pull.workout),
        (ExerciseType.strength, 4, '8–10', false, 2, 'Спина + Бицепс'));
    final curl = ex('Сгибания рук на нижнем блоке (канат)');
    expect((curl.sets, curl.repsTarget, curl.dropSet), (3, '12', true));
    final plank = ex('Планка с подъёмом ног');
    expect((plank.type, plank.sets, plank.repsTarget, plank.order), (ExerciseType.timed, 3, '30–45', 1));
    final row = ex('Гребной тренажёр');
    expect((row.type, row.sets, row.note), (ExerciseType.cardio, 1, '5 минут.'));
    final walk = ex('Ходьба на дорожке');
    expect((walk.type, walk.note, walk.workout), (ExerciseType.cardio, '5–7%, 5–7 минут.', 'Ноги + Кор'));
    expect(ex('Свободна программа на пресс х20').type, ExerciseType.strength);
  });
  test('подходы и дроп-сет', () {
    final s = rows('Тяга верхнего блока к груди (широкий)', 2025, 9, 9);
    expect(s.map((j) => (j.setNo, j.partNo, j.weight, j.reps)), [
      (1, 1, 35.0, 10), (2, 1, 45.0, 8), (3, 1, 40.0, 9),
      (4, 1, 40.0, 9), (4, 2, 30.0, 8), (4, 3, 20.0, 10),
    ]);
    expect(s.every((j) => j.workout == 'Спина + Бицепс'), isTrue);
  });
  test('k-й раздел берёт k-ю дату заголовка, даже если даты не по порядку', () {
    expect(rows('Тяга верхнего блока к груди (широкий)', 2026, 11, 6), hasLength(4));
    expect(rows('Планка с подъёмом ног', 2026, 11, 4), hasLength(3));
    expect(rows('Ходьба на дорожке', 2026, 11, 8), hasLength(1));
  });
  test('заметка в скобках', () {
    final s = rows('Сгибания рук на нижнем блоке (канат)', 2026, 11, 6);
    expect(s.map((j) => (j.weight, j.reps, j.note)), [(15.0, 12, 'у стены'), (15.0, 12, ''), (15.0, 12, '')]);
  });
  test('планка — секунды по подходам', () {
    expect(rows('Планка с подъёмом ног', 2025, 9, 11).map((j) => (j.setNo, j.seconds, j.weight)),
        [(1, 30, null), (2, 30, null), (3, 30, null)]);
  });
  test('кардио: ккал, минуты, остальное в заметку', () {
    final a = rows('Гребной тренажёр', 2026, 11, 6).single;
    expect((a.kcal, a.minutes, a.note), (64, null, ''));
    final b = rows('Ходьба на дорожке', 2025, 9, 13).single;
    expect((b.kcal, b.minutes, b.note), (57, 7.0, '7% 5.5s'));
  });
  test('три числа через точку у силового — повторы без веса', () {
    expect(rows('Свободна программа на пресс х20', 2026, 11, 8).map((j) => (j.setNo, j.weight, j.reps)),
        [(1, null, 20), (2, null, 20), (3, null, 20)]);
  });
  test('вес с запятой', () {
    final j = rows('Жим гантелей лёжа', 2026, 11, 4).single;
    expect((j.weight, j.reps), (7.5, 10));
  });
  test('пустые и нулевые ячейки и колонка без дат не дают строк', () {
    expect(rows('Гребной тренажёр', 2025, 9, 9), isEmpty);
    expect(r.journal.where((j) => (j.weight ?? 1) == 0 && (j.reps ?? 1) == 0), isEmpty);
    expect(r.journal.map((j) => j.date).toSet(), hasLength(6));
  });
  test('неразборная ячейка — одно предупреждение с адресом', () {
    expect(r.warnings, ['R8C2: сорок']);
  });
  test('ID уникальны и результат читается кодеком журнала', () {
    expect(r.journal.map((j) => j.id).toSet(), hasLength(r.journal.length));
    final back = parseJournal([journalHeader, ...r.journal.map(journalRowToCells)]);
    expect(back.errors, isEmpty);
    expect(back.items, r.journal);
  });
  group('находки на настоящей таблице', () {
    final real = parseLegacy(const [
      ['Упражнение', '09.09.2025\n11.09.2025\n13.09.2025', '16.09.2025\n18.09.2025\n20.09.2025'],
      ['ВТ. Сп+Биц'],
      ['эллипс 5 минут + \nлёгкая активация плеч.', '38к', 'Skip'],
      ['Подъёмы на носки\n3×15–20', '40.20 не Смит \n40.20\n40.20', 'skip'],
      ['Свободна программа\nна пресс х20', '20.20.20 свободная', ''],
    ]);
    test('skip — пропуск без предупреждения', () {
      expect(real.warnings, isEmpty);
      expect(real.journal.where((j) => j.date == DateTime.utc(2025, 9, 16)), isEmpty);
    });
    test('заметка после подхода без скобок', () {
      final s = real.journal.where((j) => j.exercise == 'Подъёмы на носки').toList();
      expect(s.map((j) => (j.weight, j.reps, j.note)), [(40.0, 20, 'не Смит'), (40.0, 20, ''), (40.0, 20, '')]);
      final abs = real.journal.where((j) => j.exercise.startsWith('Свободна')).toList();
      expect(abs.map((j) => (j.reps, j.note)), [(20, 'свободная'), (20, ''), (20, '')]);
    });
    test('название кардио — текст до первой цифры, с заглавной буквы', () {
      final e = real.program.first;
      expect((e.name, e.note), ('Эллипс', '5 минут + лёгкая активация плеч.'));
    });
  });

  test('колонка с данными, но без трёх дат в заголовке, даёт предупреждение', () {
    final r = parseLegacy(const [
      ['Упражнение', '09.09.2025\n11.09.2025', '16.09.2025\n18.09.2025\n20.09.2025'],
      ['ВТ. Сп+Биц'],
      ['Тяга\n4×8–10', '35.10\n45.8', '40.10'],
      ['Жим\n4×8–10', '0.0\n0.0', ''],
    ]);
    expect(r.warnings, ['C2: в заголовке не три даты, колонка пропущена']);
    expect(r.journal, hasLength(1));
  });

  test('ячейки CSV: дробные числа с запятой, чтобы таблица не приняла их за дату', () {
    expect(toCsvCells(['a', 60, 7.5, 2.0, '']), ['a', 60, '7,5', 2, '']);
  });
}
