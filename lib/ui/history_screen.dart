import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/exercise_key.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'exercise_screen.dart';
import 'format.dart';
import 'progress_screen.dart';
import 'today_screen.dart' show doneColor;

typedef _HistoryData = ({Set<DateTime> days, List<String> archive});

final _historyDataProvider = FutureProvider.autoDispose<_HistoryData>((ref) async {
  ref.watch(revisionProvider);
  final journal = ref.watch(journalStoreProvider);
  final program = await ref.watch(programStoreProvider).program();
  final current = {for (final e in program) exerciseKey(e.name)};
  final names = await journal.exerciseNames();
  return (
    days: {for (final s in await journal.sessions()) s.date},
    archive: [
      for (final n in names)
        if (!current.contains(exerciseKey(n))) n
    ]..sort(),
  );
});

/// Календарь тренировок и архив упражнений, убранных из программы.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  DateTime? _month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = ref.watch(todayDateProvider);
    final month = _month ?? DateTime.utc(today.year, today.month);
    final data = ref.watch(_historyDataProvider).value;
    final days = data?.days ?? const <DateTime>{};
    final archive = data?.archive ?? const <String>[];

    final daysInMonth = DateTime.utc(month.year, month.month + 1, 0).day;
    final leading = month.weekday - 1;
    void shift(int by) =>
        setState(() => _month = DateTime.utc(month.year, month.month + by));

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Row(
            children: [
              IconButton(
                  tooltip: 'Предыдущий месяц',
                  onPressed: () => shift(-1),
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Text(
                    '${monthsNominative[month.month - 1]} ${month.year}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium),
              ),
              IconButton(
                  tooltip: 'Следующий месяц',
                  onPressed: () => shift(1),
                  icon: const Icon(Icons.chevron_right)),
            ],
          ),
          Row(
            children: [
              for (final d in const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'])
                Expanded(
                  child: Center(
                    child: Text(d,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < leading; i++) const SizedBox.shrink(),
              for (var day = 1; day <= daysInMonth; day++)
                _DayCell(
                  date: DateTime.utc(month.year, month.month, day),
                  hasWorkout:
                      days.contains(DateTime.utc(month.year, month.month, day)),
                  isToday: DateTime.utc(month.year, month.month, day) == today,
                ),
            ],
          ),
          if (archive.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Архив упражнений', style: theme.textTheme.titleMedium),
            Text('Упражнения, которых больше нет в программе',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            for (final name in archive)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  dense: true,
                  title: Text(name),
                  trailing: const Icon(Icons.show_chart),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ProgressScreen(exerciseName: name))),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell(
      {required this.date, required this.hasWorkout, required this.isToday});
  final DateTime date;
  final bool hasWorkout;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: Key('day-${date.day}'),
      borderRadius: BorderRadius.circular(12),
      onTap: hasWorkout
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => DayScreen(date: date)))
          : null,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: hasWorkout ? theme.colorScheme.secondaryContainer : null,
          border: isToday
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${date.day}', style: theme.textTheme.bodyMedium),
            if (hasWorkout)
              Container(
                key: Key('day-mark-${date.day}'),
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 2),
                decoration: const BoxDecoration(
                    color: doneColor, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}

typedef _DayData = ({List<JournalRow> rows, List<ProgramExercise> program});

final _dayProvider =
    FutureProvider.autoDispose.family<_DayData, DateTime>((ref, date) async {
  ref.watch(revisionProvider);
  return (
    rows: await ref.watch(journalStoreProvider).rowsOn(date),
    program: await ref.watch(programStoreProvider).program(),
  );
});

/// Тренировка за выбранную дату с возможностью исправить подходы.
class DayScreen extends ConsumerWidget {
  const DayScreen({super.key, required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_dayProvider(date)).value;
    final rows = data?.rows ?? const <JournalRow>[];
    final groups = <String, List<JournalRow>>{};
    for (final r in rows) {
      groups.putIfAbsent(exerciseKey(r.exercise), () => []).add(r);
    }

    ProgramExercise exerciseFor(List<JournalRow> group) {
      final key = exerciseKey(group.first.exercise);
      for (final e in data?.program ?? const <ProgramExercise>[]) {
        if (exerciseKey(e.name) == key) return e;
      }
      // Упражнения уже нет в программе: восстанавливаем описание по записям.
      return ProgramExercise(
        workout: group.first.workout,
        order: 0,
        name: group.first.exercise,
        type: inferType(group),
        sets: group.map((r) => r.setNo).toSet().length,
        dropSet: group.any((r) => r.partNo > 1),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(formatLongDate(date))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            if (rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                    {for (final r in rows) r.workout}.join(', '),
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            for (final group in groups.values)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(group.first.exercise),
                  subtitle: Text(formatSets(group)),
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ExerciseScreen(
                          exercise: exerciseFor(group), date: date))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
