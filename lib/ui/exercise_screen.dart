import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../domain/exercise_key.dart';
import '../domain/models.dart';
import '../domain/prefill.dart';
import '../providers.dart';
import 'format.dart';
import 'progress_screen.dart';
import 'today_screen.dart' show doneColor;
import 'widgets/stepper_field.dart';

typedef _Rows = ({List<JournalRow> today, List<JournalRow> last});

/// Подходы упражнения за день и прошлая тренировка с ним.
final _rowsProvider = FutureProvider.autoDispose
    .family<_Rows, ({String key, DateTime date})>((ref, arg) async {
  ref.watch(revisionProvider);
  final journal = ref.watch(journalStoreProvider);
  final day = await journal.rowsOn(arg.date);
  return (
    today: [for (final r in day) if (exerciseKey(r.exercise) == arg.key) r],
    last: await journal.lastSessionOf(arg.key, before: arg.date),
  );
});

/// Ввод подходов упражнения [exercise] за дату [date].
class ExerciseScreen extends ConsumerStatefulWidget {
  const ExerciseScreen({super.key, required this.exercise, required this.date});
  final ProgramExercise exercise;
  final DateTime date;

  @override
  ConsumerState<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends ConsumerState<ExerciseScreen> {
  final _note = TextEditingController();
  double _weight = 0, _reps = 0, _seconds = 0, _minutes = 0, _kcal = 0;

  /// Номер подхода, для которого заполнены поля; null — нужно заполнить.
  int? _draftFor;

  /// Редактируемая запись или null, если вводится новый подход.
  JournalRow? _editing;

  ProgramExercise get _ex => widget.exercise;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _fill({double? weight, int? reps, int? seconds, double? minutes, int? kcal}) {
    _weight = weight ?? 0;
    _reps = (reps ?? 0).toDouble();
    _seconds = (seconds ?? 0).toDouble();
    _minutes = minutes ?? 0;
    _kcal = (kcal ?? 0).toDouble();
  }

  JournalRow _row(String id, int setNo, int partNo) {
    final strength = _ex.type == ExerciseType.strength;
    return JournalRow(
      id: id,
      date: dateOnly(widget.date),
      workout: _ex.workout,
      exercise: _ex.name,
      setNo: setNo,
      partNo: partNo,
      weight: strength ? _weight : null,
      reps: strength ? _reps.round() : null,
      seconds: _ex.type == ExerciseType.timed ? _seconds.round() : null,
      minutes: _ex.type == ExerciseType.cardio ? _minutes : null,
      kcal: _ex.type == ExerciseType.cardio ? _kcal.round() : null,
      note: _note.text.trim(),
    );
  }

  Future<void> _save(JournalRow row) async {
    await ref.read(journalStoreProvider).upsert(row);
    ref.read(syncRunnerProvider).schedule();
    if (!mounted) return;
    setState(() {
      _editing = null;
      _draftFor = null;
      _note.clear();
    });
  }

  Future<void> _delete(JournalRow row) async {
    await ref.read(journalStoreProvider).delete(row.id);
    ref.read(syncRunnerProvider).schedule();
    if (!mounted) return;
    setState(() {
      _editing = null;
      _draftFor = null;
      _note.clear();
    });
  }

  void _startEdit(JournalRow row) => setState(() {
        _editing = row;
        _fill(weight: row.weight, reps: row.reps, seconds: row.seconds,
            minutes: row.minutes, kcal: row.kcal);
        _note.text = row.note;
      });

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(_rowsProvider(
        (key: exerciseKey(_ex.name), date: dateOnly(widget.date))));
    return Scaffold(
      // Название в теле экрана: длинные названия не помещаются в заголовок.
      appBar: AppBar(title: Text(_ex.workout)),
      body: SafeArea(
        child: switch (rows) {
          AsyncValue(:final value?) => _body(context, value),
          AsyncValue(:final error?) =>
            Center(child: Text('Не удалось открыть данные: $error')),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _body(BuildContext context, _Rows rows) {
    final theme = Theme.of(context);
    final today = rows.today;
    final lastSetNo =
        today.fold<int>(0, (m, r) => r.setNo > m ? r.setNo : m);
    final nextSetNo = lastSetNo + 1;

    if (_editing == null && _draftFor != nextSetNo) {
      final d = prefillSet(
          exercise: _ex, setNo: nextSetNo, today: today, lastSession: rows.last);
      _fill(weight: d.weight, reps: d.reps, seconds: d.seconds,
          minutes: d.minutes, kcal: d.kcal);
      _draftFor = nextSetNo;
    }

    final bySet = <int, List<JournalRow>>{};
    for (final r in today) {
      bySet.putIfAbsent(r.setNo, () => []).add(r);
    }
    final single = _ex.type == ExerciseType.cardio && _ex.sets == 1;
    final editing = _editing;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        Text(_ex.name, style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
            single
                ? targetText(_ex)
                : '${targetText(_ex)} · подход $nextSetNo из ${_ex.sets}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (rows.last.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 8),
            color: theme.colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Прошлый раз: ${formatSets(rows.last)}'),
            ),
          ),
        const SizedBox(height: 4),
        for (final setNo in bySet.keys.toList()..sort())
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                    width: 28,
                    child: Text('$setNo',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant))),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final r in bySet[setNo]!
                        ..sort((a, b) => a.partNo.compareTo(b.partNo)))
                        ActionChip(
                          label: Text(formatSets([r])),
                          side: editing?.id == r.id
                              ? BorderSide(color: theme.colorScheme.primary, width: 2)
                              : null,
                          onPressed: () => _startEdit(r),
                        ),
                      if (bySet[setNo]!.length > 1)
                        // Весь подход одной строкой — как в журнале.
                        Text(formatSets(bySet[setNo]!),
                            style: theme.textTheme.bodySmall),
                      const Icon(Icons.check, size: 18, color: doneColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        ..._fields(),
        TextField(
          key: const Key('note'),
          controller: _note,
          decoration: const InputDecoration(
              labelText: 'Заметка', isDense: true, border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        if (editing != null) ...[
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: () =>
                _save(_row(editing.id, editing.setNo, editing.partNo)),
            child: const Text('Сохранить'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _editing = null;
                    _draftFor = null;
                    _note.clear();
                  }),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error),
                  onPressed: () => _delete(editing),
                  child: const Text('Удалить'),
                ),
              ),
            ],
          ),
        ] else ...[
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: () =>
                _save(_row(const Uuid().v4(), nextSetNo, 1)),
            child: Text(single ? 'Готово' : 'Готово — подход $nextSetNo'),
          ),
          if (_ex.dropSet && lastSetNo > 0) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _save(_row(
                  const Uuid().v4(), lastSetNo, bySet[lastSetNo]!.length + 1)),
              child: const Text('+ часть дроп-сета'),
            ),
          ],
        ],
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ProgressScreen(exerciseName: _ex.name))),
          icon: const Icon(Icons.show_chart),
          label: const Text('График прогресса'),
        ),
      ],
    );
  }

  List<Widget> _fields() => switch (_ex.type) {
        ExerciseType.strength => [
            StepperField(
                key: const Key('stepper-weight'),
                value: _weight,
                step: _ex.weightStep,
                label: 'кг · шаг ${formatNumber(_ex.weightStep)}',
                onChanged: (v) => setState(() => _weight = v)),
            StepperField(
                key: const Key('stepper-reps'),
                value: _reps,
                step: 1,
                integer: true,
                label: 'повторов',
                onChanged: (v) => setState(() => _reps = v)),
          ],
        ExerciseType.timed => [
            StepperField(
                key: const Key('stepper-seconds'),
                value: _seconds,
                step: 5,
                integer: true,
                label: 'секунды',
                onChanged: (v) => setState(() => _seconds = v)),
          ],
        ExerciseType.cardio => [
            StepperField(
                key: const Key('stepper-minutes'),
                value: _minutes,
                step: 1,
                label: 'минуты',
                onChanged: (v) => setState(() => _minutes = v)),
            StepperField(
                key: const Key('stepper-kcal'),
                value: _kcal,
                step: 1,
                integer: true,
                label: 'ккал',
                onChanged: (v) => setState(() => _kcal = v)),
          ],
      };
}
