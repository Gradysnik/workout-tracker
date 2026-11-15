import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/exercise_key.dart';
import '../domain/models.dart';
import '../providers.dart';
import '../sheets/sheet_codec.dart' show weekdayName;
import 'format.dart';
import 'progress_screen.dart';

typedef _ProgramData = ({
  List<ProgramExercise> program,
  List<ScheduleEntry> schedule
});

final _programProvider = FutureProvider.autoDispose<_ProgramData>((ref) async {
  ref.watch(revisionProvider);
  final store = ref.watch(programStoreProvider);
  return (program: await store.program(), schedule: await store.schedule());
});

/// Программа и расписание из таблицы — только для чтения.
class ProgramScreen extends ConsumerWidget {
  const ProgramScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final data = ref.watch(_programProvider).value;
    final program = data?.program ?? const <ProgramExercise>[];
    final schedule = data?.schedule ?? const <ScheduleEntry>[];
    final errors = ref.watch(syncServiceProvider)?.lastProgramErrors ?? const [];

    // Сначала тренировки в порядке расписания, затем те, что без дня.
    final all = workoutsOf(program);
    final ordered = <({String workout, String? day})>[];
    final placed = <String>{};
    for (final s in schedule.toList()
      ..sort((a, b) => a.weekday.compareTo(b.weekday))) {
      for (final w in all) {
        if (exerciseKey(w) == exerciseKey(s.workout)) {
          ordered.add((workout: w, day: weekdayName(s.weekday)));
          placed.add(exerciseKey(w));
        }
      }
    }
    for (final w in all) {
      if (!placed.contains(exerciseKey(w))) ordered.add((workout: w, day: null));
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (errors.isNotEmpty)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ошибки в таблице',
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer)),
                    for (final e in errors)
                      Text(e,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer)),
                  ],
                ),
              ),
            ),
          if (data != null && program.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: Text('Программа пуста')),
            ),
          for (final w in ordered) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text(w.day == null ? w.workout : '${w.day} · ${w.workout}',
                  style: theme.textTheme.titleMedium),
            ),
            for (final e in exercisesOf(program, w.workout))
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  dense: true,
                  title: Text(e.name),
                  subtitle: Text(targetText(e)),
                  trailing: const Icon(Icons.show_chart, size: 20),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ProgressScreen(exerciseName: e.name))),
                ),
              ),
          ],
          if (program.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
              child: Text(
                  'Программа и расписание правятся в Google-таблице, '
                  'в листах «Программа» и «Расписание».',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}
