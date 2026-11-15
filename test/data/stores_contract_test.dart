import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/drift/database.dart';
import 'package:workout_tracker/data/drift/drift_stores.dart';
import 'package:workout_tracker/data/memory_stores.dart';
import 'package:workout_tracker/data/stores.dart';
import 'package:workout_tracker/domain/models.dart';

JournalRow row(String id, int day, String exercise, int setNo,
        {int part = 1, double w = 40, int r = 10, String workout = 'A'}) =>
    JournalRow(id: id, date: DateTime.utc(2026, 11, day), workout: workout,
        exercise: exercise, setNo: setNo, partNo: part, weight: w, reps: r);

typedef Stores = ({JournalStore journal, ProgramStore program, MetaStore meta});

void contract(String name, Stores Function() make) {
  group(name, () {
    late Stores s;
    setUp(() => s = make());

    test('upsert с тем же id заменяет строку', () async {
      await s.journal.upsert(row('1', 10, 'Тяга', 1));
      await s.journal.upsert(row('1', 10, 'Тяга', 1, w: 45));
      final rows = await s.journal.historyOf('тяга');
      expect(rows.single.weight, 45);
    });
    test('lastSessionOf — только последняя дата строго раньше before, по ключу', () async {
      await s.journal.upsert(row('1', 3, 'Тяга', 1));
      await s.journal.upsert(row('3', 10, 'ТЯГА ', 2, w: 60));
      await s.journal.upsert(row('2', 10, 'Тяга', 1, w: 50));
      await s.journal.upsert(row('4', 17, 'Тяга', 1, w: 70));
      await s.journal.upsert(row('5', 10, 'Жим', 1));
      final last = await s.journal.lastSessionOf('тяга', before: DateTime.utc(2026, 11, 17));
      expect(last.map((r) => r.id), ['2', '3']);
      expect(await s.journal.lastSessionOf('тяга', before: DateTime.utc(2026, 11, 3)), isEmpty);
    });
    test('historyOf — по дате, подходу и части', () async {
      await s.journal.upsert(row('b', 10, 'Тяга', 2, part: 2));
      await s.journal.upsert(row('a', 10, 'Тяга', 2));
      await s.journal.upsert(row('c', 3, 'Тяга', 1));
      expect((await s.journal.historyOf('тяга')).map((r) => r.id), ['c', 'a', 'b']);
    });
    test('watchSession показывает строки дня и тренировки и обновляется', () async {
      await s.journal.upsert(row('1', 10, 'Тяга', 1));
      await s.journal.upsert(row('2', 10, 'Жим', 1, workout: 'B'));
      await s.journal.upsert(row('3', 11, 'Тяга', 1));
      final stream = s.journal.watchSession(DateTime.utc(2026, 11, 10), 'a');
      expect((await stream.first).map((r) => r.id), ['1']);
      final next = stream.firstWhere((rows) => rows.length == 2);
      await s.journal.upsert(row('4', 10, 'Тяга', 2));
      expect((await next).map((r) => r.id), ['1', '4']);
    });
    test('delete прячет строку, но оставляет её в очереди как удалённую', () async {
      await s.journal.upsert(row('1', 10, 'Тяга', 1));
      await s.journal.markSynced(['1']);
      await s.journal.delete('1');
      expect(await s.journal.historyOf('тяга'), isEmpty);
      expect(await s.journal.sessions(), isEmpty);
      final p = await s.journal.pending();
      expect(p.map((e) => (e.row.id, e.deleted)), [('1', true)]);
      await s.journal.markSynced(['1']);
      expect(await s.journal.pending(), isEmpty);
    });
    test('новая строка ждёт отправки, после markSynced — нет, после правки — снова', () async {
      await s.journal.upsert(row('1', 10, 'Тяга', 1));
      expect((await s.journal.pending()).map((e) => (e.row.id, e.deleted)), [('1', false)]);
      await s.journal.markSynced(['1']);
      expect(await s.journal.pending(), isEmpty);
      await s.journal.upsert(row('1', 10, 'Тяга', 1, w: 99));
      expect((await s.journal.pending()).single.row.weight, 99);
    });
    test('replaceAll заменяет журнал и ничего не ставит в очередь', () async {
      await s.journal.upsert(row('1', 10, 'Тяга', 1));
      await s.journal.replaceAll([row('x', 3, 'Жим', 1), row('y', 3, 'Жим', 2)]);
      expect(await s.journal.pending(), isEmpty);
      expect(await s.journal.historyOf('тяга'), isEmpty);
      expect(await s.journal.historyOf('жим'), hasLength(2));
    });
    test('sessions без дубликатов, по дате', () async {
      await s.journal.upsert(row('1', 10, 'Тяга', 1));
      await s.journal.upsert(row('2', 10, 'Жим', 1));
      await s.journal.upsert(row('3', 3, 'Тяга', 1, workout: 'B'));
      expect(await s.journal.sessions(), [
        (date: DateTime.utc(2026, 11, 3), workout: 'B'),
        (date: DateTime.utc(2026, 11, 10), workout: 'A'),
      ]);
    });
    test('exerciseNames — последнее написание для каждого ключа', () async {
      await s.journal.upsert(row('1', 3, 'тяга', 1));
      await s.journal.upsert(row('2', 10, 'Тяга', 1));
      await s.journal.upsert(row('3', 10, 'Жим', 1));
      expect((await s.journal.exerciseNames())..sort(), ['Жим', 'Тяга']);
    });
    test('строка со всеми полями сохраняется без потерь', () async {
      final full = JournalRow(id: 'f', date: DateTime.utc(2026, 11, 10), workout: 'A',
          exercise: 'Ходьба', setNo: 1, partNo: 1, weight: 7.5, reps: 3, seconds: 30,
          minutes: 7.5, kcal: 57, note: '7% 5.5s');
      await s.journal.upsert(full);
      expect((await s.journal.historyOf('ходьба')).single, full);
    });
    test('программа и расписание заменяются целиком, порядок сохраняется', () async {
      const p1 = ProgramExercise(workout: 'A', order: 2, name: 'Тяга', type: ExerciseType.strength,
          sets: 4, repsTarget: '8–10', dropSet: true, weightStep: 5, note: 'n');
      const p2 = ProgramExercise(workout: 'A', order: 1, name: 'Гребля', type: ExerciseType.cardio, sets: 1);
      const sch = ScheduleEntry(weekday: DateTime.tuesday, workout: 'A');
      await s.program.replace([p1, p2], [sch]);
      expect(await s.program.program(), [p1, p2]);
      expect(await s.program.schedule(), [sch]);
      await s.program.replace([], []);
      expect(await s.program.program(), isEmpty);
    });
    test('meta хранит и стирает значения', () async {
      expect(await s.meta.get('k'), isNull);
      await s.meta.set('k', 'v');
      expect(await s.meta.get('k'), 'v');
      await s.meta.set('k', null);
      expect(await s.meta.get('k'), isNull);
    });
  });
}

void main() {
  contract('в памяти', () =>
      (journal: MemoryJournalStore(), program: MemoryProgramStore(), meta: MemoryMetaStore()));
  contract('drift', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return (journal: DriftJournalStore(db), program: DriftProgramStore(db), meta: DriftMetaStore(db));
  });
}
