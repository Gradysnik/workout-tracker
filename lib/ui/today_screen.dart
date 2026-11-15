import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers.dart';
import 'exercise_screen.dart';
import 'format.dart';

const doneColor = Color(0xFF4ADE80);

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(todayProvider);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await ref.read(syncRunnerProvider).run();
        },
        child: switch (data) {
          AsyncValue(:final value?) => _Body(value),
          AsyncValue(:final error?) => _Message('Не удалось открыть данные: $error'),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [Text(text, textAlign: TextAlign.center)],
      );
}

class _Body extends ConsumerWidget {
  const _Body(this.data);
  final TodayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final workout = data.workout;
    if (workout == null) return const _EmptyProgram();

    final done = data.exercises.where((e) => e.done).length;
    final choice = data.choice;
    final missed = data.manual ? null : choice?.missedWorkout;
    final subtitle = [
      formatLongDate(data.date),
      '$done из ${data.exercises.length} выполнено',
      if (!data.manual && choice!.early) 'Следующая по расписанию',
    ].join(' · ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        PopupMenuButton<String>(
          tooltip: 'Выбрать тренировку',
          onSelected: (w) =>
              ref.read(selectedWorkoutProvider.notifier).select(w),
          itemBuilder: (_) => [
            for (final w in data.workouts) PopupMenuItem(value: w, child: Text(w))
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Flexible(
                  child: Text(workout,
                      key: const Key('workout-title'),
                      style: theme.textTheme.headlineSmall),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(subtitle,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        if (missed != null)
          Card(
            color: theme.colorScheme.tertiaryContainer,
            margin: const EdgeInsets.only(top: 12),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.history),
              title: Text('$missed не выполнена — сделать сегодня?'),
              onTap: () =>
                  ref.read(selectedWorkoutProvider.notifier).select(missed),
            ),
          ),
        const SizedBox(height: 8),
        for (final e in data.exercises) _ExerciseTile(e, data.date),
      ],
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile(this.status, this.date);
  final ExerciseStatus status;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final e = status.exercise;
    final best = bestText(status.last);
    final subtitle = status.today.isNotEmpty
        ? formatSets(status.today)
        : [targetText(e), if (best != null) 'прошлый раз $best'].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(e.name),
        subtitle: Text(subtitle),
        trailing: status.done
            ? const Icon(Icons.check_circle, color: doneColor)
            : const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ExerciseScreen(exercise: e, date: date))),
      ),
    );
  }
}

class _EmptyProgram extends ConsumerWidget {
  const _EmptyProgram();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncServiceProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 48),
        const Icon(Icons.table_chart_outlined, size: 48),
        const SizedBox(height: 16),
        Text('Заполните лист «Программа» в таблице',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
            'Упражнения и расписание задаются в Google-таблице. '
            'После правки потяните этот экран вниз, чтобы обновить.',
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        if (sync != null)
          Center(
            child: FilledButton.tonal(
              onPressed: () async {
                final url = await sync.spreadsheetUrl();
                if (url != null) {
                  await launchUrl(Uri.parse(url),
                      mode: LaunchMode.externalApplication);
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Сначала войдите в Google в настройках')));
                }
              },
              child: const Text('Открыть таблицу'),
            ),
          ),
      ],
    );
  }
}
