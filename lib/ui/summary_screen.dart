import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/models.dart';
import '../domain/summary.dart';
import '../providers.dart';
import 'format.dart';
import 'today_screen.dart' show doneColor;

final _summaryProvider = FutureProvider.autoDispose
    .family<WorkoutSummary, ({String workout, DateTime date})>((ref, arg) async {
  final program = await ref.watch(programStoreProvider).program();
  final statuses = await loadExercises(
      ref.watch(journalStoreProvider), program, arg.workout, dateOnly(arg.date));
  return summarize([
    for (final s in statuses)
      (exercise: s.exercise, today: s.today, last: s.last)
  ]);
});

/// Итог тренировки: поздравление и сравнение с прошлым разом.
class WorkoutSummaryScreen extends ConsumerWidget {
  const WorkoutSummaryScreen(
      {super.key, required this.workout, required this.date});
  final String workout;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final data =
        ref.watch(_summaryProvider((workout: workout, date: date)));
    return Scaffold(
      appBar: AppBar(title: Text(workout)),
      body: SafeArea(
        child: switch (data) {
          AsyncValue(:final value?) => ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                const Icon(Icons.emoji_events, size: 56, color: doneColor),
                const SizedBox(height: 8),
                Text('Тренировка окончена, ты красавчик! 💪',
                    key: const Key('summary-title'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(_headline(value),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                for (final r in value.results) _ResultTile(r),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56)),
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Готово'),
                ),
              ],
            ),
          AsyncValue(:final error?) =>
            Center(child: Text('Не удалось открыть данные: $error')),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  static String _headline(WorkoutSummary s) {
    if (s.results.isEmpty) return 'Сегодня подходов не записано';
    final done = plural(s.results.length, 'упражнение', 'упражнения', 'упражнений');
    if (s.compared == 0) return '$done · прошлых тренировок для сравнения нет';
    return '$done · лучше прошлого раза: ${s.improved} из ${s.compared}';
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile(this.result);
  final ExerciseResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = result;
    final delta = r.delta;
    final (IconData icon, Color color, String text) = delta == null
        ? (Icons.fiber_new, theme.colorScheme.primary, 'в первый раз')
        : delta > 0
            ? (Icons.trending_up, doneColor,
                '+${formatNumber(delta)} ${r.unit}${_pct(r)}')
            : delta < 0
                ? (Icons.trending_down, theme.colorScheme.error,
                    '${formatNumber(delta)} ${r.unit}${_pct(r)}')
                : (Icons.trending_flat, theme.colorScheme.onSurfaceVariant,
                    'как в прошлый раз');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(r.exercise.name),
        subtitle: Text(
            '${formatNumber(r.value)} ${r.unit}'
            '${r.previous == null ? '' : ' · было ${formatNumber(r.previous!)}'}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: TextStyle(color: color)),
            const SizedBox(width: 6),
            Icon(icon, color: color),
          ],
        ),
      ),
    );
  }

  static String _pct(ExerciseResult r) {
    final p = r.percent;
    if (p == null) return '';
    return ' (${p > 0 ? '+' : ''}${p.round()}%)';
  }
}
