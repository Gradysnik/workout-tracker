import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workout_tracker/domain/models.dart';
import 'package:workout_tracker/ui/progress_screen.dart';

import 'harness.dart';

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.seed();
  });

  testWidgets('силовое: три метрики, график и сессии от новых к старым', (t) async {
    await h.pump(t, const ProgressScreen(exerciseName: 'Тяга верхнего блока'));
    for (final chip in ['Макс. вес', 'Объём', 'Повторы']) {
      expect(find.widgetWithText(ChoiceChip, chip), findsOneWidget);
    }
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('с 3 ноя 2026 · 2 тренировки'), findsOneWidget);
    final newer = t.getTopLeft(find.text('10 ноя 2026')).dy;
    final older = t.getTopLeft(find.text('3 ноя 2026')).dy;
    expect(newer, lessThan(older));
    expect(find.text('40×10 · 55×10 · 55×10 · 60×10'), findsOneWidget);
  });

  testWidgets('переключение метрики меняет значения графика', (t) async {
    await h.pump(t, const ProgressScreen(exerciseName: 'Тяга верхнего блока'));
    List<double> ys() => t.widget<LineChart>(find.byType(LineChart))
        .data.lineBarsData.single.spots.map((s) => s.y).toList();
    expect(ys(), [50, 60]);
    await t.tap(find.widgetWithText(ChoiceChip, 'Объём'));
    await t.pumpAndSettle();
    expect(ys(), [900, 2100]);
    expect(t.widget<LineChart>(find.byType(LineChart)).data.lineBarsData.single.color,
        const Color(0xFF5B9DFF));
  });

  testWidgets('упражнение на время: только «Секунды»', (t) async {
    await h.pump(t, const ProgressScreen(exerciseName: 'Планка'));
    expect(find.widgetWithText(ChoiceChip, 'Секунды'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Макс. вес'), findsNothing);
  });

  testWidgets('без истории — сообщение, а не пустой график', (t) async {
    await h.pump(t, const ProgressScreen(exerciseName: 'Новое упражнение'));
    expect(find.text('Пока нет записей'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('упражнение, убранное из программы, показывает свою историю', (t) async {
    const old = ProgramExercise(workout: wA, order: 9, name: 'Старое упражнение', type: ExerciseType.strength, sets: 3);
    await h.journal.upsert(jr(3, old, 1, w: 20, r: 12));
    await h.pump(t, const ProgressScreen(exerciseName: 'старое  упражнение'));
    expect(find.text('20×12'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Макс. вес'), findsOneWidget);
  });
}
