import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/data/memory_stores.dart';
import 'package:workout_tracker/domain/models.dart';
import 'package:workout_tracker/sheets/sheet_codec.dart';
import 'package:workout_tracker/sheets/sync_service.dart';

import 'fake_gateway.dart';

JournalRow row(String id, {double w = 40, int setNo = 1}) => JournalRow(
    id: id, date: DateTime.utc(2026, 11, 10), workout: 'A', exercise: 'Тяга',
    setNo: setNo, partNo: 1, weight: w, reps: 10);

void main() {
  late FakeSheetsGateway gw;
  late MemoryJournalStore journal;
  late MemoryProgramStore program;
  late MemoryMetaStore meta;
  late SyncService sync;

  setUp(() {
    gw = FakeSheetsGateway();
    journal = MemoryJournalStore();
    program = MemoryProgramStore();
    meta = MemoryMetaStore();
    sync = SyncService(gw, journal, program, meta);
  });

  List<List<Object?>> sheetRows() => gw.only[journalSheet]!;
  List<JournalRow> sheetJournal() => parseJournal(sheetRows()).items;

  group('ensureSpreadsheet', () {
    test('создаёт таблицу с тремя листами и заголовками и запоминает id', () async {
      final id = await sync.ensureSpreadsheet();
      expect(gw.titles[id], 'Workout Tracker');
      expect(gw.only, {
        'Программа': [programHeader],
        'Расписание': [scheduleHeader],
        'Журнал': [journalHeader],
      });
      expect(await meta.get('spreadsheetId'), id);
      expect(await sync.spreadsheetUrl(), 'https://docs.google.com/spreadsheets/d/$id');
    });
    test('находит существующую по названию и не создаёт вторую', () async {
      final first = await sync.ensureSpreadsheet();
      final other = SyncService(gw, journal, program, MemoryMetaStore());
      expect(await other.ensureSpreadsheet(), first);
      expect(gw.spreadsheets, hasLength(1));
    });
    test('с сохранённым id не обращается к сети', () async {
      await sync.ensureSpreadsheet();
      gw.calls.clear();
      await sync.ensureSpreadsheet();
      expect(gw.calls, isEmpty);
    });
  });

  group('pullProgram', () {
    test('загружает программу и расписание, возвращает ошибки разбора', () async {
      await sync.ensureSpreadsheet();
      gw.only[programSheet]!.addAll([
        ['A', 1, 'Тяга', 'силовое', 4, '8–10'],
        ['A', 2, 'Странное', 'йога', 1],
      ]);
      gw.only[scheduleSheet]!.add(['Вт', 'A']);
      final errors = await sync.pullProgram();
      expect((await program.program()).map((e) => e.name), ['Тяга']);
      expect(await program.schedule(), const [ScheduleEntry(weekday: DateTime.tuesday, workout: 'A')]);
      expect(errors, hasLength(1));
      expect(sync.lastProgramErrors, errors);
    });
    test('пустой лист очищает локальную программу', () async {
      await program.replace(const [
        ProgramExercise(workout: 'A', order: 1, name: 'Старое', type: ExerciseType.strength, sets: 3)
      ], const []);
      await sync.pullProgram();
      expect(await program.program(), isEmpty);
    });
  });

  group('pushJournal', () {
    test('новые строки уходят одним добавлением, очередь пустеет', () async {
      await journal.upsert(row('1'));
      await journal.upsert(row('2', setNo: 2));
      expect(await sync.pushJournal(), 2);
      expect(gw.calls.where((c) => c.startsWith('append')), ['append Журнал 2']);
      expect(sheetJournal().map((r) => r.id), ['1', '2']);
      expect(await journal.pending(), isEmpty);
    });
    test('без изменений не обращается к сети', () async {
      await sync.ensureSpreadsheet();
      gw.calls.clear();
      expect(await sync.pushJournal(), 0);
      expect(gw.calls, isEmpty);
    });
    test('после обрыва повторная отправка не создаёт дубликатов', () async {
      await journal.upsert(row('1'));
      await journal.upsert(row('2', setNo: 2));
      gw.failAfterAppend = true;
      await expectLater(sync.pushJournal(), throwsException);
      expect(await journal.pending(), hasLength(2));
      await sync.pushJournal();
      expect(sheetJournal().map((r) => r.id), ['1', '2']);
      expect(await journal.pending(), isEmpty);
    });
    test('правка отправленной строки обновляет ту же строку листа', () async {
      await journal.upsert(row('1'));
      await journal.upsert(row('2', setNo: 2));
      await sync.pushJournal();
      await journal.upsert(row('2', setNo: 2, w: 99));
      await sync.pushJournal();
      expect(sheetRows(), hasLength(3));
      expect(sheetJournal().map((r) => (r.id, r.weight)), [('1', 40.0), ('2', 99.0)]);
    });
    test('удаление отправленных строк убирает их из листа, не оставляя пустых', () async {
      for (final id in ['1', '2', '3', '4']) {
        await journal.upsert(row(id, setNo: int.parse(id)));
      }
      await sync.pushJournal();
      await journal.delete('1');
      await journal.delete('3');
      await journal.upsert(row('4', setNo: 4, w: 77));
      await journal.upsert(row('5', setNo: 5));
      await sync.pushJournal();
      expect(sheetRows(), hasLength(4));
      expect(sheetJournal().map((r) => (r.id, r.weight)), [('2', 40.0), ('4', 77.0), ('5', 40.0)]);
      expect(await journal.pending(), isEmpty);
    });
    test('строка, созданная и удалённая до отправки, в лист не попадает', () async {
      await journal.upsert(row('1'));
      await journal.delete('1');
      await sync.pushJournal();
      expect(sheetJournal(), isEmpty);
      expect(await journal.pending(), isEmpty);
    });
  });

  test('правка строки во время отправки уходит следующей синхронизацией', () async {
    await journal.upsert(row('1'));
    gw.onAppend = () async {
      gw.onAppend = null;
      await journal.upsert(row('1', w: 99));
    };
    await sync.pushJournal();
    expect((await journal.pending()).single.row.weight, 99);
    await sync.pushJournal();
    expect(sheetJournal().map((r) => (r.id, r.weight)), [('1', 99.0)]);
    expect(await journal.pending(), isEmpty);
  });

  group('restoreJournal', () {
    test('сначала отправляет своё, потом заменяет журнал содержимым листа', () async {
      await sync.ensureSpreadsheet();
      gw.only[journalSheet]!.add(journalRowToCells(row('из-таблицы', w: 70)));
      await journal.upsert(row('локальная'));
      expect(await sync.restoreJournal(), isEmpty);
      expect((await journal.historyOf('тяга')).map((r) => r.id).toSet(), {'из-таблицы', 'локальная'});
      expect(await journal.pending(), isEmpty);
    });
    test('при неразборных строках ничего не заменяет и возвращает ошибки', () async {
      await sync.ensureSpreadsheet();
      gw.only[journalSheet]!.addAll([
        journalRowToCells(row('хорошая', w: 70)),
        ['плохая', 'вчера', 'A', 'Тяга', 1, 1, '60кг', 10],
      ]);
      await journal.replaceAll([row('старая')]);
      final errors = await sync.restoreJournal();
      expect(errors, ['Журнал, строка 3: непонятная дата «вчера»']);
      expect((await journal.historyOf('тяга')).map((r) => r.id), ['старая']);
    });
    test('с ignoreErrors восстанавливает разобранные строки', () async {
      await sync.ensureSpreadsheet();
      gw.only[journalSheet]!.addAll([
        journalRowToCells(row('хорошая', w: 70)),
        ['плохая', 'вчера', 'A', 'Тяга', 1, 1, 60, 10],
      ]);
      await journal.replaceAll([row('старая')]);
      await sync.restoreJournal(ignoreErrors: true);
      expect((await journal.historyOf('тяга')).map((r) => r.id), ['хорошая']);
    });
    test('одновременно с синхронизацией не дублирует строки', () async {
      await journal.upsert(row('1'));
      await Future.wait([sync.syncAll(), sync.restoreJournal(), sync.pushJournal()]);
      expect(sheetJournal().map((r) => r.id), ['1']);
    });
  });

  test('forgetSpreadsheet заставляет искать таблицу заново', () async {
    final id = await sync.ensureSpreadsheet();
    await sync.forgetSpreadsheet();
    expect(await sync.spreadsheetUrl(), isNull);
    gw.calls.clear();
    expect(await sync.ensureSpreadsheet(), id);
    expect(gw.calls, ['find']);
  });

  group('syncAll', () {
    test('без сети возвращает ошибку и не бросает, очередь цела', () async {
      await journal.upsert(row('1'));
      gw.offline = true;
      final report = await sync.syncAll();
      expect(report.failure, isNotNull);
      expect(await journal.pending(), hasLength(1));
    });
    test('успешная синхронизация: программа загружена, журнал отправлен', () async {
      await journal.upsert(row('1'));
      final report = await sync.syncAll();
      expect((report.failure, report.pushed), (null, 1));
    });
    test('одновременные вызовы не дублируют строки', () async {
      await journal.upsert(row('1'));
      await Future.wait([sync.syncAll(), sync.syncAll()]);
      expect(sheetJournal().map((r) => r.id), ['1']);
    });
  });
}
