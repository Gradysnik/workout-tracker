import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workout_tracker/domain/models.dart';
import 'package:workout_tracker/sheets/sync_service.dart';
import 'package:workout_tracker/ui/exercise_screen.dart';
import 'package:workout_tracker/ui/history_screen.dart';
import 'package:workout_tracker/ui/program_screen.dart';
import 'package:workout_tracker/ui/progress_screen.dart';

import '../sheets/fake_gateway.dart';
import 'harness.dart';

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.seed();
  });
  const old = ProgramExercise(workout: wA, order: 9, name: 'Старое упражнение', type: ExerciseType.strength, sets: 3);

  group('история', () {
    testWidgets('календарь текущего месяца отмечает дни тренировок', (t) async {
      await h.pump(t, const Scaffold(body: HistoryScreen()));
      expect(find.text('Ноябрь 2026'), findsOneWidget);
      for (final d in [3, 10, 12, 14]) {
        expect(find.byKey(Key('day-mark-$d')), findsOneWidget);
      }
      expect(find.byKey(const Key('day-mark-11')), findsNothing);
    });

    testWidgets('переключение месяца', (t) async {
      await h.pump(t, const Scaffold(body: HistoryScreen()));
      await t.tap(find.byIcon(Icons.chevron_left));
      await t.pumpAndSettle();
      expect(find.text('Октябрь 2026'), findsOneWidget);
      expect(find.byKey(const Key('day-mark-10')), findsNothing);
    });

    testWidgets('день открывает тренировку, упражнение — правку за эту дату', (t) async {
      await h.pump(t, const Scaffold(body: HistoryScreen()));
      await t.tap(find.byKey(const Key('day-10')));
      await t.pumpAndSettle();
      expect(find.text('Вторник, 10 ноября'), findsOneWidget);
      expect(find.text('40×10 · 55×10 · 55×10 · 60×10'), findsOneWidget);
      await t.tap(find.text('Тяга верхнего блока'));
      await t.pumpAndSettle();
      final screen = t.widget<ExerciseScreen>(find.byType(ExerciseScreen));
      expect((screen.date, screen.exercise.name, screen.exercise.weightStep), (nov(10), 'Тяга верхнего блока', 5));
    });

    testWidgets('день с упражнением вне программы тоже открывается', (t) async {
      await h.journal.upsert(jr(10, old, 1, w: 20, r: 12));
      await h.pump(t, const Scaffold(body: HistoryScreen()));
      await t.tap(find.byKey(const Key('day-10')));
      await t.pumpAndSettle();
      await t.tap(find.text('Старое упражнение'));
      await t.pumpAndSettle();
      expect(t.widget<ExerciseScreen>(find.byType(ExerciseScreen)).exercise.type, ExerciseType.strength);
    });

    testWidgets('архив: упражнения из журнала, которых нет в программе', (t) async {
      await h.journal.upsert(jr(3, old, 1, w: 20, r: 12));
      await h.pump(t, const Scaffold(body: HistoryScreen()));
      expect(find.text('Архив упражнений'), findsOneWidget);
      expect(find.text('Старое упражнение'), findsOneWidget);
      expect(find.text('Тяга верхнего блока'), findsNothing);
      await t.ensureVisible(find.text('Старое упражнение'));
      await t.tap(find.text('Старое упражнение'));
      await t.pumpAndSettle();
      expect(find.byType(ProgressScreen), findsOneWidget);
    });

    testWidgets('без архива раздел не показывается', (t) async {
      await h.pump(t, const Scaffold(body: HistoryScreen()));
      expect(find.text('Архив упражнений'), findsNothing);
    });
  });

  group('программа', () {
    testWidgets('тренировки по дням расписания, упражнения по порядку с целями', (t) async {
      await h.pump(t, const Scaffold(body: ProgramScreen()));
      expect(find.text('Вт · $wA'), findsOneWidget);
      expect(find.text('Чт · $wB'), findsOneWidget);
      final rowY = t.getTopLeft(find.text('Гребной тренажёр')).dy;
      final pullY = t.getTopLeft(find.text('Тяга верхнего блока')).dy;
      expect(rowY, lessThan(pullY));
      expect(find.text('4×8–10, дроп-сет'), findsOneWidget);
    });

    testWidgets('тренировка без дня в расписании тоже видна', (t) async {
      await h.program.replace(const [bench, rdl],
          const [ScheduleEntry(weekday: DateTime.thursday, workout: wB)]);
      await h.pump(t, const Scaffold(body: ProgramScreen()));
      expect(find.text('Чт · $wB'), findsOneWidget);
      expect(find.text(wC), findsOneWidget);
    });

    testWidgets('ошибки заполнения таблицы показаны сверху', (t) async {
      final gw = FakeSheetsGateway();
      h.sync = SyncService(gw, h.journal, h.program, h.meta);
      await h.sync!.ensureSpreadsheet();
      gw.only['Программа']!.addAll([
        ['A', 1, 'Тяга', 'силовое', 4, '8–10'],
        ['A', 2, 'Странное', 'йога', 1],
      ]);
      await h.sync!.pullProgram();
      await h.pump(t, const Scaffold(body: ProgramScreen()));
      expect(find.textContaining('Программа, строка 3: неизвестный тип «йога»'), findsOneWidget);
    });

    testWidgets('пустая программа — подсказка', (t) async {
      await h.program.replace(const [], const []);
      await h.pump(t, const Scaffold(body: ProgramScreen()));
      expect(find.text('Программа пуста'), findsOneWidget);
    });
  });
}
