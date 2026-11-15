import '../data/stores.dart';
import 'sheet_codec.dart';
import 'sheets_gateway.dart';

const spreadsheetTitle = 'Workout Tracker';
const _idKey = 'spreadsheetId';

class SyncReport {
  const SyncReport({this.programErrors = const [], this.pushed = 0, this.failure});
  final List<String> programErrors;
  final int pushed;
  final Object? failure;
}

class SyncService {
  SyncService(this._gateway, this._journal, this._program, this._meta);

  final SheetsGateway _gateway;
  final JournalStore _journal;
  final ProgramStore _program;
  final MetaStore _meta;

  /// Ошибки заполнения листов при последней загрузке программы.
  List<String> lastProgramErrors = const [];

  Future<SyncReport>? _running;

  /// Хвост очереди операций с таблицей: синхронизация, отправка и
  /// восстановление выполняются строго по одной, иначе две отправки могли бы
  /// прочитать лист до добавления строк и продублировать их.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Забывает таблицу (при выходе из аккаунта): при следующей синхронизации
  /// она будет найдена или создана заново.
  Future<void> forgetSpreadsheet() => _meta.set(_idKey, null);

  Future<String?> spreadsheetUrl() async {
    final id = await _meta.get(_idKey);
    return id == null ? null : 'https://docs.google.com/spreadsheets/d/$id';
  }

  Future<String> ensureSpreadsheet() async {
    var id = await _meta.get(_idKey);
    if (id != null) return id;
    id = await _gateway.findSpreadsheet(spreadsheetTitle) ??
        await _gateway.createSpreadsheet(spreadsheetTitle, const {
          programSheet: programHeader,
          scheduleSheet: scheduleHeader,
          journalSheet: journalHeader,
        });
    await _meta.set(_idKey, id);
    return id;
  }

  Future<List<String>> pullProgram() => _serial(_pullProgram);

  Future<List<String>> _pullProgram() async {
    final id = await ensureSpreadsheet();
    final program = parseProgram(await _gateway.readSheet(id, programSheet));
    final schedule = parseSchedule(await _gateway.readSheet(id, scheduleSheet));
    await _program.replace(program.items, schedule.items);
    return lastProgramErrors = [...program.errors, ...schedule.errors];
  }

  /// Отправляет ожидающие строки журнала. Возвращает их количество.
  ///
  /// Строки находятся в листе по колонке ID, поэтому повтор после обрыва
  /// обновляет уже добавленные строки, а не создаёт дубликаты.
  Future<int> pushJournal() => _serial(_pushJournal);

  Future<int> _pushJournal() async {
    final pending = await _journal.pending();
    if (pending.isEmpty) return 0;
    final id = await ensureSpreadsheet();
    final sheet = await _gateway.readSheet(id, journalSheet);
    final rowNumbers = <String, int>{
      for (var i = 1; i < sheet.length; i++)
        if (sheet[i].isNotEmpty && '${sheet[i][0] ?? ''}'.isNotEmpty)
          '${sheet[i][0]}': i + 1
    };

    // Порядок важен: правки по номерам строк, затем добавление в конец,
    // и только потом удаление, которое сдвигает номера.
    final toAppend = <List<Object?>>[];
    final toDelete = <int>[];
    for (final p in pending) {
      final rowNumber = rowNumbers[p.row.id];
      if (p.deleted) {
        if (rowNumber != null) toDelete.add(rowNumber);
      } else if (rowNumber != null) {
        await _gateway.updateRow(
            id, journalSheet, rowNumber, journalRowToCells(p.row));
      } else {
        toAppend.add(journalRowToCells(p.row));
      }
    }
    if (toAppend.isNotEmpty) {
      await _gateway.appendRows(id, journalSheet, toAppend);
    }
    if (toDelete.isNotEmpty) {
      await _gateway.deleteRows(id, journalSheet, toDelete);
    }
    await _journal.markSynced(pending);
    return pending.length;
  }

  /// Заново загружает журнал из таблицы, предварительно отправив своё.
  ///
  /// Возвращает строки листа, которые не удалось разобрать. Если такие есть,
  /// журнал на телефоне не трогается — иначе они молча пропали бы;
  /// с [ignoreErrors] восстанавливаются только разобранные строки.
  Future<List<String>> restoreJournal({bool ignoreErrors = false}) =>
      _serial(() async {
        await _pushJournal();
        final id = await ensureSpreadsheet();
        final parsed = parseJournal(await _gateway.readSheet(id, journalSheet));
        if (parsed.errors.isNotEmpty && !ignoreErrors) return parsed.errors;
        await _journal.replaceAll(parsed.items);
        return const [];
      });

  /// Полная синхронизация. Не бросает: ошибка возвращается в отчёте.
  /// Одновременные вызовы разделяют один и тот же проход.
  Future<SyncReport> syncAll() => _running ??=
      _serial(_syncAll).whenComplete(() => _running = null);

  Future<SyncReport> _syncAll() async {
    try {
      final errors = await _pullProgram();
      final pushed = await _pushJournal();
      return SyncReport(programErrors: errors, pushed: pushed);
    } catch (e) {
      return SyncReport(programErrors: lastProgramErrors, failure: e);
    }
  }
}
