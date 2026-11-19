import 'package:workout_tracker/sheets/sheets_gateway.dart';

/// Таблица в памяти вместо Google Sheets.
class FakeSheetsGateway implements SheetsGateway {
  final spreadsheets = <String, Map<String, List<List<Object?>>>>{};
  final titles = <String, String>{};
  final calls = <String>[];
  bool failAfterAppend = false;
  bool offline = false;

  /// Вызывается посреди отправки, после добавления строк в лист.
  Future<void> Function()? onAppend;

  Map<String, List<List<Object?>>> get only => spreadsheets.values.single;

  void _net(String call) {
    calls.add(call);
    if (offline) throw Exception('нет сети');
  }

  @override
  Future<String?> findSpreadsheet(String title) async {
    _net('find');
    for (final e in titles.entries) {
      if (e.value == title) return e.key;
    }
    return null;
  }

  @override
  Future<String> createSpreadsheet(
      String title, Map<String, List<String>> headersBySheet) async {
    _net('create');
    final id = 'sheet-${spreadsheets.length + 1}';
    titles[id] = title;
    spreadsheets[id] = {
      for (final e in headersBySheet.entries) e.key: [List<Object?>.of(e.value)]
    };
    return id;
  }

  @override
  Future<List<List<Object?>>> readSheet(String spreadsheetId, String sheet) async {
    _net('read $sheet');
    return [for (final r in spreadsheets[spreadsheetId]![sheet]!) List.of(r)];
  }

  @override
  Future<void> appendRows(
      String spreadsheetId, String sheet, List<List<Object?>> rows) async {
    _net('append $sheet ${rows.length}');
    spreadsheets[spreadsheetId]![sheet]!.addAll(rows.map(List.of));
    await onAppend?.call();
    if (failAfterAppend) {
      failAfterAppend = false;
      throw Exception('обрыв связи');
    }
  }

  @override
  Future<void> updateRow(String spreadsheetId, String sheet, int rowNumber,
      List<Object?> cells) async {
    _net('update $sheet $rowNumber');
    spreadsheets[spreadsheetId]![sheet]![rowNumber - 1] = List.of(cells);
  }

  @override
  Future<void> deleteRows(
      String spreadsheetId, String sheet, List<int> rowNumbers) async {
    _net('delete $sheet $rowNumbers');
    final rows = spreadsheets[spreadsheetId]![sheet]!;
    for (final n in rowNumbers.toList()..sort((a, b) => b.compareTo(a))) {
      rows.removeAt(n - 1);
    }
  }

  @override
  Future<void> replaceRows(
      String spreadsheetId, String sheet, List<List<Object?>> rows) async {
    _net('replace $sheet ${rows.length}');
    final data = spreadsheets[spreadsheetId]![sheet]!;
    data
      ..removeRange(1, data.length)
      ..addAll(rows.map(List.of));
  }
}
