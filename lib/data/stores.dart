import '../domain/models.dart';

typedef PendingRow = ({JournalRow row, bool deleted});
typedef SessionRef = ({DateTime date, String workout});

/// Журнал подходов. Источник правды — локальное хранилище;
/// изменения помечаются «к отправке» и уходят в таблицу при синхронизации.
abstract class JournalStore {
  /// Сохраняет строку (новую или с тем же id) и ставит её в очередь отправки.
  Future<void> upsert(JournalRow row);

  /// Мягкое удаление: строка пропадает из выборок и ждёт отправки как удалённая.
  Future<void> delete(String id);

  Stream<List<JournalRow>> watchSession(DateTime date, String workout);

  /// Строки последней тренировки с этим упражнением строго раньше [before].
  Future<List<JournalRow>> lastSessionOf(String exerciseKey,
      {required DateTime before});

  Future<List<JournalRow>> historyOf(String exerciseKey);
  Future<List<JournalRow>> rowsOn(DateTime date);
  Future<List<SessionRef>> sessions();

  /// Последнее написание названия для каждого упражнения в журнале.
  Future<List<String>> exerciseNames();

  Future<List<PendingRow>> pending();

  /// Снимает отметку «к отправке» с отправленных строк; удалённые стираются
  /// окончательно. [pushed] — снимок [pending], который ушёл в таблицу:
  /// строка, изменённая или удалённая после снимка, остаётся в очереди.
  Future<void> markSynced(Iterable<PendingRow> pushed);

  /// Заменяет весь журнал; все строки считаются отправленными.
  Future<void> replaceAll(List<JournalRow> rows);

  Stream<void> changes();
}

abstract class ProgramStore {
  Future<void> replace(
      List<ProgramExercise> program, List<ScheduleEntry> schedule);
  Future<List<ProgramExercise>> program();
  Future<List<ScheduleEntry>> schedule();
  Stream<void> changes();
}

abstract class MetaStore {
  Future<String?> get(String key);
  Future<void> set(String key, String? value);
}

int compareRows(JournalRow a, JournalRow b) {
  var c = a.date.compareTo(b.date);
  if (c == 0) c = a.setNo.compareTo(b.setNo);
  if (c == 0) c = a.partNo.compareTo(b.partNo);
  return c;
}
