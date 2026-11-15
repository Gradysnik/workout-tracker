import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;

import 'google_auth.dart';
import 'sheets_gateway.dart';

/// Работа с таблицей через Google Sheets API и Drive API.
class GoogleSheetsGateway implements SheetsGateway {
  GoogleSheetsGateway(this._auth);
  final GoogleAuth _auth;

  Future<T> _with<T>(Future<T> Function(http.Client client) body) async {
    final client = await _auth.client();
    try {
      return await body(client);
    } finally {
      client.close();
    }
  }

  String _range(String sheet, [String cells = 'A:Z']) => "'$sheet'!$cells";

  @override
  Future<String?> findSpreadsheet(String title) => _with((client) async {
        final escaped = title.replaceAll("'", r"\'");
        final found = await drive.DriveApi(client).files.list(
              q: "name = '$escaped' and "
                  "mimeType = 'application/vnd.google-apps.spreadsheet' and "
                  'trashed = false',
              spaces: 'drive',
              orderBy: 'createdTime',
              $fields: 'files(id)',
            );
        final files = found.files ?? const [];
        return files.isEmpty ? null : files.first.id;
      });

  @override
  Future<String> createSpreadsheet(
          String title, Map<String, List<String>> headersBySheet) =>
      _with((client) async {
        final api = sheets.SheetsApi(client);
        final created = await api.spreadsheets.create(sheets.Spreadsheet(
          properties: sheets.SpreadsheetProperties(title: title),
          sheets: [
            for (final name in headersBySheet.keys)
              sheets.Sheet(
                  properties: sheets.SheetProperties(
                      title: name,
                      gridProperties:
                          sheets.GridProperties(frozenRowCount: 1)))
          ],
        ));
        final id = created.spreadsheetId!;
        await api.spreadsheets.values.batchUpdate(
            sheets.BatchUpdateValuesRequest(
              valueInputOption: 'RAW',
              data: [
                for (final e in headersBySheet.entries)
                  sheets.ValueRange(range: _range(e.key, 'A1'), values: [e.value])
              ],
            ),
            id);
        return id;
      });

  @override
  Future<List<List<Object?>>> readSheet(String spreadsheetId, String sheet) =>
      _with((client) async {
        final range = await sheets.SheetsApi(client).spreadsheets.values.get(
              spreadsheetId,
              _range(sheet),
              valueRenderOption: 'UNFORMATTED_VALUE',
              dateTimeRenderOption: 'FORMATTED_STRING',
            );
        return range.values ?? const [];
      });

  @override
  Future<void> appendRows(
          String spreadsheetId, String sheet, List<List<Object?>> rows) =>
      _with((client) => sheets.SheetsApi(client).spreadsheets.values.append(
            sheets.ValueRange(values: rows),
            spreadsheetId,
            _range(sheet, 'A1'),
            valueInputOption: 'RAW',
            insertDataOption: 'INSERT_ROWS',
          ));

  @override
  Future<void> updateRow(String spreadsheetId, String sheet, int rowNumber,
          List<Object?> cells) =>
      _with((client) => sheets.SheetsApi(client).spreadsheets.values.update(
            sheets.ValueRange(values: [cells]),
            spreadsheetId,
            _range(sheet, 'A$rowNumber'),
            valueInputOption: 'RAW',
          ));

  @override
  Future<void> deleteRows(
          String spreadsheetId, String sheet, List<int> rowNumbers) =>
      _with((client) async {
        final api = sheets.SheetsApi(client);
        final meta = await api.spreadsheets
            .get(spreadsheetId, $fields: 'sheets.properties(sheetId,title)');
        final sheetId = meta.sheets!
            .firstWhere((s) => s.properties!.title == sheet)
            .properties!
            .sheetId;
        // Снизу вверх, чтобы удаление не сдвигало ещё не удалённые строки.
        final descending = rowNumbers.toList()..sort((a, b) => b.compareTo(a));
        await api.spreadsheets.batchUpdate(
            sheets.BatchUpdateSpreadsheetRequest(requests: [
              for (final n in descending)
                sheets.Request(
                    deleteDimension: sheets.DeleteDimensionRequest(
                        range: sheets.DimensionRange(
                            sheetId: sheetId,
                            dimension: 'ROWS',
                            startIndex: n - 1,
                            endIndex: n)))
            ]),
            spreadsheetId);
      });
}
