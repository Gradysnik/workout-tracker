import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workout_tracker/app.dart';

import 'package:workout_tracker/sheets/sync_service.dart';

import 'sheets/fake_gateway.dart';
import 'ui/harness.dart';

void main() {
  testWidgets('оболочка: три вкладки, открыта «Сегодня»', (t) async {
    final h = Harness();
    await h.seed();
    await h.pump(t, const HomeShell());
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.text('История'), findsOneWidget);
    expect(find.text('Программа'), findsOneWidget);
    expect(find.text('Тяга верхнего блока'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('после возвращения в приложение на другой день дата и тренировка обновляются', (t) async {
    final h = Harness();
    await h.seed();
    await h.pump(t, const HomeShell());
    expect(find.textContaining('Вторник, 17 ноября'), findsOneWidget);
    // Вручную выбрана другая тренировка — выбор действует только на этот день.
    await t.tap(find.byKey(const Key('workout-title')));
    await t.pumpAndSettle();
    await t.tap(find.text(wC).last);
    await t.pumpAndSettle();

    h.today = nov(19);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.textContaining('Четверг, 19 ноября'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('workout-title'))).data, wB);
  });

  testWidgets('при сворачивании приложения неотправленные подходы уходят в таблицу', (t) async {
    final h = Harness();
    await h.seed();
    final gw = FakeSheetsGateway();
    h.sync = SyncService(gw, h.journal, h.program, h.meta);
    await h.pump(t, const HomeShell());
    await h.journal.upsert(jr(17, pulldown, 1, w: 60, r: 10));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pumpAndSettle();
    expect(gw.calls, contains('append Журнал 1'));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
  });
}
