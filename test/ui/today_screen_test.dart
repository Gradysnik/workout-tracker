import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workout_tracker/sheets/sync_service.dart';
import 'package:workout_tracker/ui/exercise_screen.dart';
import 'package:workout_tracker/ui/today_screen.dart';

import '../sheets/fake_gateway.dart';
import 'harness.dart';

Finder tile(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(ListTile));
String title(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('workout-title'))).data!;

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.seed();
  });

  testWidgets('показывает только упражнения тренировки дня, по порядку', (t) async {
    await h.pump(t, const Scaffold(body: TodayScreen()));
    expect(title(t), wA);
    final names = t.widgetList<ListTile>(find.byType(ListTile))
        .map((l) => (l.title as Text).data).toList();
    expect(names, ['Гребной тренажёр', 'Тяга верхнего блока', 'Тяга горизонтального блока']);
    expect(find.text('Вторник, 17 ноября · 0 из 3 выполнено'), findsOneWidget);
  });

  testWidgets('под упражнением цель и результат прошлого раза', (t) async {
    await h.pump(t, const Scaffold(body: TodayScreen()));
    expect(find.descendant(of: tile('Тяга горизонтального блока'),
        matching: find.text('4×8–10, дроп-сет · прошлый раз 60×10')), findsOneWidget);
    expect(find.descendant(of: tile('Гребной тренажёр'),
        matching: find.text('5 минут. · прошлый раз 5 мин · 71 ккал')), findsOneWidget);
  });

  testWidgets('выполненное упражнение отмечено галочкой и показывает сегодняшние подходы', (t) async {
    for (var i = 1; i <= 4; i++) {
      await h.journal.upsert(jr(17, pulldown, i, w: 60, r: 10));
    }
    await h.journal.upsert(jr(17, seatedRow, 1, w: 60, r: 10));
    await h.pump(t, const Scaffold(body: TodayScreen()));
    expect(find.descendant(of: tile('Тяга верхнего блока'), matching: find.byIcon(Icons.check_circle)), findsOneWidget);
    expect(find.descendant(of: tile('Тяга горизонтального блока'), matching: find.byIcon(Icons.check_circle)), findsNothing);
    expect(find.descendant(of: tile('Тяга верхнего блока'),
        matching: find.text('60×10 · 60×10 · 60×10 · 60×10')), findsOneWidget);
    expect(find.textContaining('1 из 3 выполнено'), findsOneWidget);
  });

  testWidgets('напоминает о пропущенной тренировке и переключается на неё', (t) async {
    h.today = nov(19);
    await h.pump(t, const Scaffold(body: TodayScreen()));
    expect(title(t), wB);
    expect(find.text('$wA не выполнена — сделать сегодня?'), findsOneWidget);
    await t.tap(find.text('$wA не выполнена — сделать сегодня?'));
    await t.pumpAndSettle();
    expect(title(t), wA);
    expect(find.text('Тяга верхнего блока'), findsOneWidget);
  });

  testWidgets('в день без тренировки — следующая по расписанию', (t) async {
    h.today = nov(16);
    await h.pump(t, const Scaffold(body: TodayScreen()));
    expect(title(t), wA);
    expect(find.textContaining('Следующая по расписанию'), findsOneWidget);
  });

  testWidgets('другую тренировку можно выбрать из меню заголовка', (t) async {
    await h.pump(t, const Scaffold(body: TodayScreen()));
    await t.tap(find.byKey(const Key('workout-title')));
    await t.pumpAndSettle();
    await t.tap(find.text(wC).last);
    await t.pumpAndSettle();
    expect(title(t), wC);
    expect(find.text('Румынская тяга'), findsOneWidget);
    expect(find.text('Тяга верхнего блока'), findsNothing);
  });

  testWidgets('пустая программа — подсказка, а не ошибка', (t) async {
    await h.program.replace(const [], const []);
    await h.pump(t, const Scaffold(body: TodayScreen()));
    expect(find.text('Заполните лист «Программа» в таблице'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('программа без расписания — показывает первую тренировку', (t) async {
    await h.program.replace(const [bench, rdl], const []);
    await h.pump(t, const Scaffold(body: TodayScreen()));
    expect(title(t), wB);
    expect(t.takeException(), isNull);
  });

  testWidgets('жест «потянуть вниз» запускает синхронизацию', (t) async {
    final gw = FakeSheetsGateway();
    h.sync = SyncService(gw, h.journal, h.program, h.meta);
    await h.journal.upsert(jr(17, pulldown, 1, w: 60, r: 10));
    await h.pump(t, const Scaffold(body: TodayScreen()));
    await t.fling(find.text('Тяга верхнего блока'), const Offset(0, 400), 1000);
    await t.pumpAndSettle();
    expect(gw.calls, contains('append Журнал 1'));
  });

  testWidgets('касание по упражнению открывает ввод подхода', (t) async {
    await h.pump(t, const Scaffold(body: TodayScreen()));
    await t.tap(find.text('Тяга верхнего блока'));
    await t.pumpAndSettle();
    expect(find.byType(ExerciseScreen), findsOneWidget);
  });
}
