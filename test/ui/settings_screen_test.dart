import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/sheets/sheet_codec.dart';
import 'package:workout_tracker/sheets/sync_service.dart';
import 'package:workout_tracker/ui/settings_screen.dart';

import '../sheets/fake_gateway.dart';
import 'harness.dart';

void main() {
  late Harness h;
  late FakeSheetsGateway gw;
  setUp(() async {
    h = Harness();
    await h.seed();
    gw = FakeSheetsGateway();
  });
  Future<void> tapText(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text));
    await t.tap(find.text(text));
    await t.pumpAndSettle();
  }

  testWidgets('без синхронизации — пометка демо-режима', (t) async {
    await h.pump(t, const SettingsScreen());
    expect(find.textContaining('Демо-режим'), findsOneWidget);
    expect(find.text('Синхронизировать'), findsNothing);
  });

  testWidgets('показывает число неотправленных строк и отправляет их', (t) async {
    h.sync = SyncService(gw, h.journal, h.program, h.meta);
    await h.journal.upsert(jr(17, pulldown, 1, w: 60, r: 10));
    await h.pump(t, const SettingsScreen());
    expect(find.text('Не отправлено: 1'), findsOneWidget);
    await tapText(t, 'Синхронизировать');
    expect(find.text('Всё отправлено'), findsOneWidget);
    expect(gw.calls, contains('append Журнал 1'));
    expect(find.text('Синхронизация выполнена'), findsOneWidget);
  });

  testWidgets('ошибка синхронизации показывается, данные остаются в очереди', (t) async {
    h.sync = SyncService(gw, h.journal, h.program, h.meta);
    await h.journal.upsert(jr(17, pulldown, 1, w: 60, r: 10));
    gw.offline = true;
    await h.pump(t, const SettingsScreen());
    await tapText(t, 'Синхронизировать');
    expect(find.textContaining('Не удалось синхронизировать'), findsOneWidget);
    expect(find.text('Не отправлено: 1'), findsOneWidget);
  });

  testWidgets('восстановление из таблицы требует подтверждения', (t) async {
    h.sync = SyncService(gw, h.journal, h.program, h.meta);
    await h.sync!.ensureSpreadsheet();
    gw.only[journalSheet]!.add(journalRowToCells(jr(1, rdl, 1, w: 99, r: 5)));
    await h.pump(t, const SettingsScreen());

    await tapText(t, 'Восстановить из таблицы');
    await tapText(t, 'Отмена');
    expect(await h.journal.historyOf('румынская тяга'), hasLength(1));

    await tapText(t, 'Восстановить из таблицы');
    await tapText(t, 'Восстановить');
    final rows = await h.journal.historyOf('румынская тяга');
    expect(rows.map((r) => r.weight), [99.0]);
    expect(await h.journal.historyOf('тяга верхнего блока'), isEmpty);
    expect(find.text('Журнал восстановлен из таблицы'), findsOneWidget);
  });

  testWidgets('вход через Google сразу создаёт таблицу и синхронизирует', (t) async {
    h.sync = SyncService(gw, h.journal, h.program, h.meta);
    h.auth = FakeGoogleAuth();
    await h.pump(t, const SettingsScreen());
    expect(find.text('Синхронизировать'), findsOneWidget);
    await tapText(t, 'Войти через Google');
    expect(find.text('user@example.com'), findsOneWidget);
    expect(gw.calls, contains('create'));
    expect(await h.sync!.spreadsheetUrl(), isNotNull);
  });

  testWidgets('отменённый вход не показывает ошибку и ничего не создаёт', (t) async {
    h.sync = SyncService(gw, h.journal, h.program, h.meta);
    h.auth = FakeGoogleAuth()..cancel = true;
    await h.pump(t, const SettingsScreen());
    await tapText(t, 'Войти через Google');
    expect(find.textContaining('Не получилось'), findsNothing);
    expect(gw.calls, isEmpty);
  });

  testWidgets('выход из аккаунта забывает таблицу', (t) async {
    h.sync = SyncService(gw, h.journal, h.program, h.meta);
    h.auth = FakeGoogleAuth();
    await h.pump(t, const SettingsScreen());
    await tapText(t, 'Войти через Google');
    await tapText(t, 'user@example.com');
    expect(find.text('Войти через Google'), findsOneWidget);
    expect(await h.sync!.spreadsheetUrl(), isNull);
  });

  testWidgets('восстановление с неразборными строками спрашивает, что делать', (t) async {
    h.sync = SyncService(gw, h.journal, h.program, h.meta);
    await h.sync!.ensureSpreadsheet();
    gw.only[journalSheet]!.addAll([
      journalRowToCells(jr(1, rdl, 1, w: 99, r: 5)),
      ['плохая', 'вчера', wC, 'Румынская тяга', 1, 1, 60, 10],
    ]);
    await h.pump(t, const SettingsScreen());
    await tapText(t, 'Восстановить из таблицы');
    await tapText(t, 'Восстановить');
    expect(find.textContaining('Журнал, строка 3: непонятная дата «вчера»'), findsOneWidget);
    expect(await h.journal.historyOf('тяга верхнего блока'), isNotEmpty);
    await tapText(t, 'Восстановить без них');
    expect((await h.journal.historyOf('румынская тяга')).map((r) => r.weight), [99.0]);
    expect(await h.journal.historyOf('тяга верхнего блока'), isEmpty);
  });
}
