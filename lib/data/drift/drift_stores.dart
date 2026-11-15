import 'package:drift/drift.dart';

import '../../domain/exercise_key.dart';
import '../../domain/models.dart';
import '../../sheets/sheet_codec.dart' show formatDate;
import '../stores.dart';
import 'database.dart';

DateTime _parseDate(String s) => DateTime.parse('${s}T00:00:00Z');

JournalRow _toRow(JournalRecord r) => JournalRow(
      id: r.id,
      date: _parseDate(r.date),
      workout: r.workout,
      exercise: r.exercise,
      setNo: r.setNo,
      partNo: r.partNo,
      weight: r.weight,
      reps: r.reps,
      seconds: r.seconds,
      minutes: r.minutes,
      kcal: r.kcal,
      note: r.note,
    );

JournalRecordsCompanion _toRecord(JournalRow r, {required bool pending}) =>
    JournalRecordsCompanion.insert(
      id: r.id,
      date: formatDate(r.date),
      workout: r.workout,
      workoutKey: exerciseKey(r.workout),
      exercise: r.exercise,
      exKey: exerciseKey(r.exercise),
      setNo: r.setNo,
      partNo: r.partNo,
      weight: Value(r.weight),
      reps: Value(r.reps),
      seconds: Value(r.seconds),
      minutes: Value(r.minutes),
      kcal: Value(r.kcal),
      note: Value(r.note),
      pending: pending,
      deleted: const Value(false),
    );

class DriftJournalStore implements JournalStore {
  DriftJournalStore(this.db);
  final AppDatabase db;

  $JournalRecordsTable get _t => db.journalRecords;

  SimpleSelectStatement<$JournalRecordsTable, JournalRecord> _live() =>
      db.select(_t)
        ..where((t) => t.deleted.equals(false))
        ..orderBy([
          (t) => OrderingTerm(expression: t.date),
          (t) => OrderingTerm(expression: t.setNo),
          (t) => OrderingTerm(expression: t.partNo),
        ]);

  Future<List<JournalRow>> _rows(
          SimpleSelectStatement<$JournalRecordsTable, JournalRecord> q) async =>
      (await q.get()).map(_toRow).toList();

  @override
  Future<void> upsert(JournalRow row) =>
      db.into(_t).insertOnConflictUpdate(_toRecord(row, pending: true));

  @override
  Future<void> delete(String id) =>
      (db.update(_t)..where((t) => t.id.equals(id))).write(
          const JournalRecordsCompanion(
              deleted: Value(true), pending: Value(true)));

  @override
  Stream<List<JournalRow>> watchSession(DateTime date, String workout) =>
      (_live()
            ..where((t) =>
                t.date.equals(formatDate(date)) &
                t.workoutKey.equals(exerciseKey(workout))))
          .watch()
          .map((rows) => rows.map(_toRow).toList());

  @override
  Future<List<JournalRow>> historyOf(String key) =>
      _rows(_live()..where((t) => t.exKey.equals(key)));

  @override
  Future<List<JournalRow>> lastSessionOf(String key,
      {required DateTime before}) async {
    final latest = await (_live()
          ..where((t) =>
              t.exKey.equals(key) &
              t.date.isSmallerThanValue(formatDate(before)))
          ..orderBy([(t) => OrderingTerm.desc(t.date)])
          ..limit(1))
        .getSingleOrNull();
    if (latest == null) return const [];
    return _rows(_live()
      ..where((t) => t.exKey.equals(key) & t.date.equals(latest.date)));
  }

  @override
  Future<List<JournalRow>> rowsOn(DateTime date) =>
      _rows(_live()..where((t) => t.date.equals(formatDate(date))));

  @override
  Future<List<SessionRef>> sessions() async {
    final q = db.selectOnly(_t, distinct: true)
      ..addColumns([_t.date, _t.workoutKey, _t.workout.max()])
      ..where(_t.deleted.equals(false))
      ..groupBy([_t.date, _t.workoutKey])
      ..orderBy([OrderingTerm(expression: _t.date)]);
    return [
      for (final r in await q.get())
        (date: _parseDate(r.read(_t.date)!), workout: r.read(_t.workout.max())!)
    ];
  }

  @override
  Future<List<String>> exerciseNames() async {
    final q = db.selectOnly(_t)
      ..addColumns([_t.exKey, _t.exercise])
      ..where(_t.deleted.equals(false))
      ..orderBy([OrderingTerm(expression: _t.date)]);
    final names = <String, String>{};
    for (final r in await q.get()) {
      names[r.read(_t.exKey)!] = r.read(_t.exercise)!;
    }
    return names.values.toList();
  }

  @override
  Future<List<PendingRow>> pending() async => [
        for (final r
            in await (db.select(_t)..where((t) => t.pending.equals(true))).get())
          (row: _toRow(r), deleted: r.deleted)
      ];

  @override
  Future<void> markSynced(Iterable<String> ids) => db.transaction(() async {
        final list = ids.toList();
        await (db.delete(_t)
              ..where((t) => t.id.isIn(list) & t.deleted.equals(true)))
            .go();
        await (db.update(_t)..where((t) => t.id.isIn(list)))
            .write(const JournalRecordsCompanion(pending: Value(false)));
      });

  @override
  Future<void> replaceAll(List<JournalRow> rows) => db.transaction(() async {
        await db.delete(_t).go();
        await db.batch((b) => b.insertAll(
            _t, [for (final r in rows) _toRecord(r, pending: false)],
            mode: InsertMode.insertOrReplace));
      });

  @override
  Stream<void> changes() => db.tableUpdates(TableUpdateQuery.onTable(_t));
}

class DriftProgramStore implements ProgramStore {
  DriftProgramStore(this.db);
  final AppDatabase db;

  @override
  Future<void> replace(List<ProgramExercise> program,
          List<ScheduleEntry> schedule) =>
      db.transaction(() async {
        await db.delete(db.programRecords).go();
        await db.delete(db.scheduleRecords).go();
        await db.batch((b) {
          b.insertAll(db.programRecords, [
            for (final (i, e) in program.indexed)
              ProgramRecordsCompanion.insert(
                position: Value(i),
                workout: e.workout,
                sortOrder: e.order,
                name: e.name,
                type: e.type.name,
                sets: e.sets,
                repsTarget: e.repsTarget,
                dropSet: e.dropSet,
                weightStep: e.weightStep,
                note: e.note,
              )
          ]);
          b.insertAll(db.scheduleRecords, [
            for (final (i, e) in schedule.indexed)
              ScheduleRecordsCompanion.insert(
                  position: Value(i), weekday: e.weekday, workout: e.workout)
          ]);
        });
      });

  @override
  Future<List<ProgramExercise>> program() async {
    final q = db.select(db.programRecords)
      ..orderBy([(t) => OrderingTerm(expression: t.position)]);
    return [
      for (final r in await q.get())
        ProgramExercise(
          workout: r.workout,
          order: r.sortOrder,
          name: r.name,
          type: ExerciseType.values.byName(r.type),
          sets: r.sets,
          repsTarget: r.repsTarget,
          dropSet: r.dropSet,
          weightStep: r.weightStep,
          note: r.note,
        )
    ];
  }

  @override
  Future<List<ScheduleEntry>> schedule() async {
    final q = db.select(db.scheduleRecords)
      ..orderBy([(t) => OrderingTerm(expression: t.position)]);
    return [
      for (final r in await q.get())
        ScheduleEntry(weekday: r.weekday, workout: r.workout)
    ];
  }

  @override
  Stream<void> changes() =>
      db.tableUpdates(TableUpdateQuery.onTable(db.programRecords));
}

class DriftMetaStore implements MetaStore {
  DriftMetaStore(this.db);
  final AppDatabase db;

  @override
  Future<String?> get(String key) async =>
      (await (db.select(db.metaRecords)..where((t) => t.key.equals(key)))
              .getSingleOrNull())
          ?.value;

  @override
  Future<void> set(String key, String? value) async {
    if (value == null) {
      await (db.delete(db.metaRecords)..where((t) => t.key.equals(key))).go();
    } else {
      await db
          .into(db.metaRecords)
          .insertOnConflictUpdate(MetaRecordsCompanion.insert(key: key, value: value));
    }
  }
}
