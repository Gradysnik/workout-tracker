import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workout_tracker/domain/models.dart';
import 'package:workout_tracker/ui/program_editor_screen.dart';

import 'harness.dart';

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.seed();
  });

  Future<void> open(WidgetTester t) async => h.pump(
      t,
      ProgramEditorScreen(
          program: await h.program.program(),
          schedule: await h.program.schedule()));

  testWidgets('сохранение без правок не меняет программу', (t) async {
    final before = await h.program.program();
    await open(t);
    await t.tap(find.byKey(const Key('save-program')));
    await t.pumpAndSettle();
    final after = await h.program.program();
    expect(after.length, before.length);
    expect(await h.program.schedule(), hasLength(3));
  });

  testWidgets('шаг, подходы, имя и порядок упражнения меняются', (t) async {
    await open(t);
    // Тяга верхнего блока — второе упражнение тренировки A.
    await t.tap(find.byKey(Key('ex-$wA-1')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ex-name')), 'Тяга сверху');
    await t.tap(find.descendant(
        of: find.byKey(const Key('stepper-sets')),
        matching: find.byIcon(Icons.add)));
    await t.tap(find.descendant(
        of: find.byKey(const Key('stepper-step')),
        matching: find.byIcon(Icons.add)));
    await t.tap(find.byKey(const Key('ex-ok')));
    await t.pumpAndSettle();
    // Поднимаем на первое место.
    await t.tap(find.descendant(
        of: find.byKey(Key('ex-$wA-1')), matching: find.byTooltip('Выше')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('save-program')));
    await t.pumpAndSettle();

    final a = (await h.program.program()).where((e) => e.workout == wA).toList()
      ..sort((x, y) => x.order.compareTo(y.order));
    expect(a.map((e) => (e.order, e.name)),
        [(1, 'Тяга сверху'), (2, 'Гребной тренажёр'), (3, 'Тяга горизонтального блока')]);
    expect(a.first.sets, 5);
    expect(a.first.weightStep, 5.5);
  });

  testWidgets('новое упражнение и удаление', (t) async {
    await open(t);
    await t.ensureVisible(find.byKey(Key('add-exercise-$wB')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('add-exercise-$wB')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ex-name')), 'Отжимания');
    await t.tap(find.byKey(const Key('ex-ok')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(Key('ex-$wB-0')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('ex-$wB-0')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('ex-delete')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ex-delete')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('save-program')));
    await t.pumpAndSettle();
    final b = (await h.program.program()).where((e) => e.workout == wB);
    expect(b.map((e) => e.name), unorderedEquals(['Планка', 'Отжимания']));
  });

  testWidgets('день расписания переназначается и сбрасывается на отдых', (t) async {
    await open(t);
    // Вторник → отдых.
    await t.tap(find.byKey(const Key('day-${DateTime.tuesday}')));
    await t.pumpAndSettle();
    await t.tap(find.text('Отдых').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('save-program')));
    await t.pumpAndSettle();
    final s = await h.program.schedule();
    expect(s.map((e) => e.weekday),
        unorderedEquals([DateTime.thursday, DateTime.saturday]));
  });

  testWidgets('пустая тренировка не сохраняется', (t) async {
    await open(t);
    await t.tap(find.byKey(const Key('add-workout')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('name-field')), 'Пустая');
    await t.tap(find.text('ОК'));
    await t.pumpAndSettle();
    // Закрываем лист нового упражнения без сохранения.
    await t.tap(find.text('Отмена'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('save-program')));
    await t.pumpAndSettle();
    expect(find.textContaining('нет упражнений'), findsOneWidget);
    expect((await h.program.program()).where((e) => e.workout == 'Пустая'),
        isEmpty);
  });
}
