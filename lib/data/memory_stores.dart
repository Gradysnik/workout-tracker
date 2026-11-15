import 'dart:async';

import '../domain/exercise_key.dart';
import '../domain/models.dart';
import 'stores.dart';

class _Entry {
  _Entry(this.row, {this.pending = true});
  JournalRow row;
  bool pending;
  bool deleted = false;
}

/// Журнал в памяти: для тестов и демо-режима.
class MemoryJournalStore implements JournalStore {
  final _entries = <String, _Entry>{};
  final _changes = StreamController<void>.broadcast();

  Iterable<JournalRow> get _live =>
      _entries.values.where((e) => !e.deleted).map((e) => e.row);

  List<JournalRow> _sorted(Iterable<JournalRow> rows) =>
      rows.toList()..sort(compareRows);

  @override
  Future<void> upsert(JournalRow row) async {
    _entries.remove(row.id);
    _entries[row.id] = _Entry(row);
    _changes.add(null);
  }

  @override
  Future<void> delete(String id) async {
    final e = _entries[id];
    if (e == null) return;
    e
      ..deleted = true
      ..pending = true;
    _changes.add(null);
  }

  List<JournalRow> _session(DateTime date, String workout) => _sorted(_live.where(
      (r) => r.date == dateOnly(date) && exerciseKey(r.workout) == exerciseKey(workout)));

  @override
  Stream<List<JournalRow>> watchSession(DateTime date, String workout) =>
      Stream.multi((controller) {
        controller.add(_session(date, workout));
        final sub = _changes.stream
            .listen((_) => controller.add(_session(date, workout)));
        controller.onCancel = sub.cancel;
      });

  @override
  Future<List<JournalRow>> historyOf(String key) async =>
      _sorted(_live.where((r) => exerciseKey(r.exercise) == key));

  @override
  Future<List<JournalRow>> lastSessionOf(String key,
      {required DateTime before}) async {
    final earlier = (await historyOf(key))
        .where((r) => r.date.isBefore(dateOnly(before)))
        .toList();
    if (earlier.isEmpty) return const [];
    return earlier.where((r) => r.date == earlier.last.date).toList();
  }

  @override
  Future<List<JournalRow>> rowsOn(DateTime date) async =>
      _sorted(_live.where((r) => r.date == dateOnly(date)));

  @override
  Future<List<SessionRef>> sessions() async {
    final seen = <String>{};
    return [
      for (final r in _sorted(_live))
        if (seen.add('${r.date}|${exerciseKey(r.workout)}'))
          (date: r.date, workout: r.workout)
    ];
  }

  @override
  Future<List<String>> exerciseNames() async {
    final names = <String, String>{};
    for (final r in _sorted(_live)) {
      names[exerciseKey(r.exercise)] = r.exercise;
    }
    return names.values.toList();
  }

  @override
  Future<List<PendingRow>> pending() async => [
        for (final e in _entries.values)
          if (e.pending) (row: e.row, deleted: e.deleted)
      ];

  @override
  Future<void> markSynced(Iterable<String> ids) async {
    for (final id in ids) {
      final e = _entries[id];
      if (e == null) continue;
      if (e.deleted) {
        _entries.remove(id);
      } else {
        e.pending = false;
      }
    }
    _changes.add(null);
  }

  @override
  Future<void> replaceAll(List<JournalRow> rows) async {
    _entries
      ..clear()
      ..addEntries(rows.map((r) => MapEntry(r.id, _Entry(r, pending: false))));
    _changes.add(null);
  }

  @override
  Stream<void> changes() => _changes.stream;
}

class MemoryProgramStore implements ProgramStore {
  List<ProgramExercise> _program = const [];
  List<ScheduleEntry> _schedule = const [];
  final _changes = StreamController<void>.broadcast();

  @override
  Future<void> replace(
      List<ProgramExercise> program, List<ScheduleEntry> schedule) async {
    _program = List.of(program);
    _schedule = List.of(schedule);
    _changes.add(null);
  }

  @override
  Future<List<ProgramExercise>> program() async => _program;

  @override
  Future<List<ScheduleEntry>> schedule() async => _schedule;

  @override
  Stream<void> changes() => _changes.stream;
}

class MemoryMetaStore implements MetaStore {
  final _values = <String, String>{};

  @override
  Future<String?> get(String key) async => _values[key];

  @override
  Future<void> set(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}
