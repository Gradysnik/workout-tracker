import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workout_tracker/domain/models.dart';
import 'package:workout_tracker/ui/exercise_screen.dart';
import 'package:workout_tracker/ui/progress_screen.dart';

import 'harness.dart';

Finder inField(String key, Finder f) =>
    find.descendant(of: find.byKey(Key('stepper-$key')), matching: f);
String value(WidgetTester t, String key) =>
    t.widget<Text>(find.byKey(Key('stepper-$key-value'))).data!;

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.seed();
  });
  Future<List<JournalRow>> today(ProgramExercise e) async =>
      (await h.journal.rowsOn(nov(17))).where((r) => r.exercise == e.name).toList();
  Future<void> open(WidgetTester t, ProgramExercise e) =>
      h.pump(t, ExerciseScreen(exercise: e, date: nov(17)));
  Future<void> tapText(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text));
    await t.tap(find.text(text));
    await t.pumpAndSettle();
    // Пауза после сохранения, в течение которой повторное касание игнорируется.
    await t.pump(const Duration(milliseconds: 600));
  }

  testWidgets('поля заполнены значениями того же подхода прошлой тренировки', (t) async {
    await open(t, seatedRow);
    expect(value(t, 'weight'), '40');
    expect(value(t, 'reps'), '10');
    expect(find.text('4×8–10, дроп-сет · подход 1 из 4'), findsOneWidget);
    expect(find.text('Прошлый раз: 40×10 · 60×10 · 60×10 · 60×10–40×10'), findsOneWidget);
  });

  testWidgets('«Готово» сохраняет подход и готовит следующий', (t) async {
    await open(t, seatedRow);
    await t.tap(inField('weight', find.byIcon(Icons.add)));
    await t.pump();
    expect(value(t, 'weight'), '45');
    await tapText(t, 'Готово — подход 1');
    final rows = await today(seatedRow);
    expect(rows.map((r) => (r.date, r.workout, r.setNo, r.partNo, r.weight, r.reps)),
        [(nov(17), wA, 1, 1, 45.0, 10)]);
    expect(rows.single.id, isNotEmpty);
    expect(find.text('4×8–10, дроп-сет · подход 2 из 4'), findsOneWidget);
    expect(value(t, 'weight'), '60');
    expect(find.text('45×10'), findsOneWidget);
  });

  testWidgets('каждый подход получает свой id', (t) async {
    await open(t, pulldown);
    await tapText(t, 'Готово — подход 1');
    await tapText(t, 'Готово — подход 2');
    final rows = await today(pulldown);
    expect(rows.map((r) => r.setNo), [1, 2]);
    expect(rows.map((r) => r.id).toSet(), hasLength(2));
    expect((await h.journal.pending()).length, 2);
  });

  testWidgets('часть дроп-сета добавляется к последнему подходу', (t) async {
    await open(t, seatedRow);
    expect(find.text('+ часть дроп-сета'), findsNothing);
    await tapText(t, 'Готово — подход 1');
    await t.tap(inField('weight', find.byIcon(Icons.remove)));
    await t.pump();
    await tapText(t, '+ часть дроп-сета');
    final rows = await today(seatedRow);
    expect(rows.map((r) => (r.setNo, r.partNo, r.weight)), [(1, 1, 40.0), (1, 2, 55.0)]);
    expect(find.text('40×10–55×10'), findsOneWidget);
    expect(find.text('4×8–10, дроп-сет · подход 2 из 4'), findsOneWidget);
  });

  testWidgets('у упражнения без дроп-сета кнопки части нет', (t) async {
    await open(t, pulldown);
    await tapText(t, 'Готово — подход 1');
    expect(find.text('+ часть дроп-сета'), findsNothing);
  });

  testWidgets('записанный подход можно исправить — id остаётся тем же', (t) async {
    final saved = jr(17, pulldown, 1, w: 60, r: 8);
    await h.journal.upsert(saved);
    await open(t, pulldown);
    await tapText(t, '60×8');
    expect(value(t, 'weight'), '60');
    expect(value(t, 'reps'), '8');
    await t.tap(inField('reps', find.byIcon(Icons.add)));
    await t.pump();
    await tapText(t, 'Сохранить');
    final rows = await today(pulldown);
    expect(rows.map((r) => (r.id, r.reps)), [(saved.id, 9)]);
    expect(find.text('Готово — подход 2'), findsOneWidget);
  });

  testWidgets('записанный подход можно удалить', (t) async {
    await h.journal.upsert(jr(17, pulldown, 1, w: 60, r: 8));
    await open(t, pulldown);
    await tapText(t, '60×8');
    await tapText(t, 'Удалить');
    expect(await today(pulldown), isEmpty);
    expect(find.text('Готово — подход 1'), findsOneWidget);
  });

  testWidgets('упражнение на время: одно поле «секунды»', (t) async {
    await open(t, plank);
    expect(value(t, 'seconds'), '40');
    expect(find.byKey(const Key('stepper-weight')), findsNothing);
    await tapText(t, 'Готово — подход 1');
    final r = (await today(plank)).single;
    expect((r.seconds, r.weight, r.reps), (40, null, null));
  });

  testWidgets('кардио: минуты и ккал', (t) async {
    await open(t, rowing);
    expect((value(t, 'minutes'), value(t, 'kcal')), ('5', '71'));
    await t.tap(inField('kcal', find.byIcon(Icons.add)));
    await t.pump();
    await tapText(t, 'Готово');
    final r = (await today(rowing)).single;
    expect((r.minutes, r.kcal, r.weight), (5.0, 72, null));
  });

  testWidgets('заметка сохраняется вместе с подходом', (t) async {
    await open(t, pulldown);
    await t.enterText(find.byKey(const Key('note')), 'у стены');
    await tapText(t, 'Готово — подход 1');
    expect((await today(pulldown)).single.note, 'у стены');
    expect(t.widget<TextField>(find.byKey(const Key('note'))).controller!.text, '');
  });

  testWidgets('подходы сверх цели не запрещены', (t) async {
    for (var i = 1; i <= 4; i++) {
      await h.journal.upsert(jr(17, pulldown, i, w: 60, r: 10));
    }
    await open(t, pulldown);
    expect(find.text('4×8–10 · подход 5 из 4'), findsOneWidget);
    await tapText(t, 'Готово — подход 5');
    expect(await today(pulldown), hasLength(5));
  });

  testWidgets('переход к графику прогресса', (t) async {
    await open(t, pulldown);
    await tapText(t, 'График прогресса');
    expect(find.byType(ProgressScreen), findsOneWidget);
  });

  testWidgets('двойное касание «Готово» сохраняет один подход', (t) async {
    await open(t, pulldown);
    await t.ensureVisible(find.text('Готово — подход 1'));
    await t.tap(find.text('Готово — подход 1'));
    await t.tap(find.text('Готово — подход 1'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect((await today(pulldown)).map((r) => r.setNo), [1]);
  });

  testWidgets('правка старого подхода сохраняет его тренировку, даже если программа изменилась', (t) async {
    const moved = ProgramExercise(workout: wC, order: 5, name: 'Тяга верхнего блока',
        type: ExerciseType.strength, sets: 4, repsTarget: '8–10', weightStep: 5);
    await h.pump(t, ExerciseScreen(exercise: moved, date: nov(10)));
    await tapText(t, '40×10');
    await t.tap(inField('reps', find.byIcon(Icons.add)));
    await t.pump();
    await tapText(t, 'Сохранить');
    final edited = (await h.journal.rowsOn(nov(10)))
        .firstWhere((r) => r.exercise == 'Тяга верхнего блока' && r.setNo == 1);
    expect((edited.workout, edited.reps), (wA, 11));
  });

  testWidgets('кардио без истории: минуты из цели программы', (t) async {
    await h.journal.delete((await h.journal.rowsOn(nov(10)))
        .firstWhere((r) => r.exercise == rowing.name).id);
    await open(t, rowing);
    expect(value(t, 'minutes'), '5');
  });

  testWidgets('«Далее по плану» и кнопка следующего упражнения', (t) async {
    await open(t, seatedRow);
    // Из тренировки A остальные: гребной тренажёр и тяга верхнего блока.
    expect(find.byKey(const Key('up-next')), findsOneWidget);
    expect(find.text('Далее по плану'), findsOneWidget);
    expect(find.text('Следующее: Гребной тренажёр'), findsOneWidget);
    await t.tap(find.byKey(const Key('next-exercise')));
    await t.pumpAndSettle();
    expect(find.text('Гребной тренажёр'), findsWidgets);
    expect(value(t, 'minutes'), '5');
  });

  testWidgets('больше трёх упражнений — список разворачивается', (t) async {
    await h.program.replace([
      for (var i = 1; i <= 5; i++)
        ProgramExercise(workout: wA, order: i, name: 'Упр $i',
            type: ExerciseType.strength, sets: 2, repsTarget: '10'),
    ], const []);
    await open(t, (await h.program.program()).first);
    expect(find.text('Упр 2'), findsOneWidget);
    expect(find.text('Упр 4'), findsOneWidget);
    expect(find.text('Упр 5'), findsNothing);
    await t.ensureVisible(find.text('Показать все (4)'));
    await t.tap(find.text('Показать все (4)'));
    await t.pumpAndSettle();
    expect(find.text('Упр 5'), findsOneWidget);
  });

  testWidgets('последний подход последнего упражнения — итог тренировки', (t) async {
    await h.program.replace(const [rowing], const []);
    await open(t, rowing);
    await tapText(t, 'Готово');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('summary-title')), findsOneWidget);
    expect(find.text('Тренировка окончена, ты красавчик! 💪'), findsOneWidget);
    expect(find.text('Гребной тренажёр'), findsOneWidget);
  });
}
