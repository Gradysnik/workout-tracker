/// Доступ к Google-таблице. Реализация — [GoogleSheetsGateway];
/// в тестах используется подделка в памяти.
abstract class SheetsGateway {
  /// Идентификатор таблицы с таким названием, созданной приложением, или null.
  Future<String?> findSpreadsheet(String title);

  /// Создаёт таблицу с листами и строкой заголовков в каждом.
  Future<String> createSpreadsheet(
      String title, Map<String, List<String>> headersBySheet);

  /// Все строки листа, включая заголовок.
  Future<List<List<Object?>>> readSheet(String spreadsheetId, String sheet);

  Future<void> appendRows(
      String spreadsheetId, String sheet, List<List<Object?>> rows);

  /// Перезаписывает строку с номером [rowNumber] (нумерация с 1).
  Future<void> updateRow(String spreadsheetId, String sheet, int rowNumber,
      List<Object?> cells);

  /// Удаляет строки листа целиком; номера — до удаления (нумерация с 1).
  Future<void> deleteRows(
      String spreadsheetId, String sheet, List<int> rowNumbers);

  /// Заменяет все строки листа, кроме заголовка, на [rows].
  Future<void> replaceRows(
      String spreadsheetId, String sheet, List<List<Object?>> rows);
}
