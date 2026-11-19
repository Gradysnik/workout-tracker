import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/exercise_key.dart';
import '../domain/models.dart';
import '../providers.dart';
import 'format.dart';
import 'widgets/stepper_field.dart';

const _typeLabels = {
  ExerciseType.strength: 'Силовое',
  ExerciseType.timed: 'Время',
  ExerciseType.cardio: 'Кардио',
};

const _weekdayLong = [
  'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота',
  'Воскресенье',
];

class _Workout {
  _Workout(this.name, this.items);
  String name;
  List<ProgramExercise> items;
}

/// Редактор программы и расписания. Сохранение пишет в Google-таблицу
/// (если вход выполнен) и в локальное хранилище.
class ProgramEditorScreen extends ConsumerStatefulWidget {
  const ProgramEditorScreen(
      {super.key, required this.program, required this.schedule});
  final List<ProgramExercise> program;
  final List<ScheduleEntry> schedule;

  @override
  ConsumerState<ProgramEditorScreen> createState() =>
      _ProgramEditorScreenState();
}

class _ProgramEditorScreenState extends ConsumerState<ProgramEditorScreen> {
  late final List<_Workout> _workouts;

  /// Тренировка на каждый день недели (1..7); null — отдых.
  late final Map<int, String?> _days;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _workouts = [
      for (final w in workoutsOf(widget.program))
        _Workout(w, exercisesOf(widget.program, w))
    ];
    _days = {for (var d = 1; d <= 7; d++) d: null};
    for (final s in widget.schedule) {
      _days.putIfAbsent(s.weekday, () => null);
      _days[s.weekday] ??= s.workout;
    }
  }

  String? _workoutNameFor(String? name) {
    if (name == null) return null;
    for (final w in _workouts) {
      if (exerciseKey(w.name) == exerciseKey(name)) return w.name;
    }
    return null;
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<String?> _askName(String title, [String initial = '']) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('name-field'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('ОК')),
        ],
      ),
    );
  }

  bool _nameTaken(String name, [_Workout? except]) => _workouts.any(
      (w) => w != except && exerciseKey(w.name) == exerciseKey(name));

  Future<void> _addWorkout() async {
    final name = (await _askName('Новая тренировка'))?.trim();
    if (name == null || name.isEmpty) return;
    if (_nameTaken(name)) return _snack('Тренировка «$name» уже есть');
    setState(() => _workouts.add(_Workout(name, [])));
    await _editExercise(_workouts.last, null);
  }

  Future<void> _renameWorkout(_Workout w) async {
    final name = (await _askName('Название тренировки', w.name))?.trim();
    if (name == null || name.isEmpty || name == w.name) return;
    if (_nameTaken(name, w)) return _snack('Тренировка «$name» уже есть');
    setState(() {
      final old = w.name;
      for (final d in _days.keys) {
        if (_days[d] != null && exerciseKey(_days[d]!) == exerciseKey(old)) {
          _days[d] = name;
        }
      }
      w.name = name;
    });
  }

  Future<void> _deleteWorkout(_Workout w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить «${w.name}»?'),
        content: const Text(
            'Тренировка уберётся из программы и расписания. '
            'Записанные подходы в журнале останутся.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _workouts.remove(w);
      for (final d in _days.keys) {
        if (_days[d] != null && exerciseKey(_days[d]!) == exerciseKey(w.name)) {
          _days[d] = null;
        }
      }
    });
  }

  /// [index] == null — новое упражнение в конец.
  Future<void> _editExercise(_Workout w, int? index) async {
    final result = await showModalBottomSheet<_SheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ExerciseSheet(
        workout: w.name,
        initial: index == null ? null : w.items[index],
      ),
    );
    if (result == null) return;
    setState(() {
      if (result.delete) {
        w.items = [...w.items]..removeAt(index!);
      } else if (index == null) {
        w.items = [...w.items, result.exercise!];
      } else {
        w.items = [...w.items]..[index] = result.exercise!;
      }
    });
  }

  void _move(_Workout w, int index, int delta) {
    final to = index + delta;
    if (to < 0 || to >= w.items.length) return;
    setState(() {
      final list = [...w.items];
      list.insert(to, list.removeAt(index));
      w.items = list;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    for (final w in _workouts) {
      if (w.items.isEmpty) {
        return _snack('В тренировке «${w.name}» нет упражнений');
      }
      final seen = <String>{};
      for (final e in w.items) {
        if (!seen.add(exerciseKey(e.name))) {
          return _snack('«${e.name}» повторяется в «${w.name}»');
        }
      }
    }
    final program = <ProgramExercise>[
      for (final w in _workouts)
        for (final (i, e) in w.items.indexed)
          ProgramExercise(
            workout: w.name,
            order: i + 1,
            name: e.name,
            type: e.type,
            sets: e.sets,
            repsTarget: e.repsTarget,
            dropSet: e.dropSet,
            weightStep: e.weightStep,
            note: e.note,
          )
    ];
    final schedule = <ScheduleEntry>[
      for (var d = 1; d <= 7; d++)
        if (_workoutNameFor(_days[d]) != null)
          ScheduleEntry(weekday: d, workout: _workoutNameFor(_days[d])!)
    ];
    setState(() => _saving = true);
    try {
      final sync = ref.read(syncServiceProvider);
      if (sync != null && ref.read(syncRunnerProvider).available) {
        await sync.savePlan(program, schedule);
      } else {
        await ref.read(programStoreProvider).replace(program, schedule);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      return _snack('Не удалось сохранить в таблицу: $e');
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = {
      for (final w in _workouts) w.name,
    }.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактор программы'),
        actions: [
          TextButton(
            key: const Key('save-program'),
            onPressed: _saving ? null : _save,
            child: const Text('Сохранить'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          Text('Расписание', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          for (var d = 1; d <= 7; d++)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(_weekdayLong[d - 1]),
              trailing: DropdownButton<String?>(
                key: Key('day-$d'),
                value: _workoutNameFor(_days[d]),
                hint: const Text('Отдых'),
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Отдых')),
                  for (final o in options)
                    DropdownMenuItem<String?>(value: o, child: Text(o)),
                ],
                onChanged: (v) => setState(() => _days[d] = v),
              ),
            ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                  child: Text('Тренировки', style: theme.textTheme.titleMedium)),
              TextButton.icon(
                key: const Key('add-workout'),
                onPressed: _addWorkout,
                icon: const Icon(Icons.add),
                label: const Text('Тренировка'),
              ),
            ],
          ),
          for (final w in _workouts) _workoutCard(theme, w),
        ],
      ),
    );
  }

  Widget _workoutCard(ThemeData theme, _Workout w) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
              child: Row(
                children: [
                  Expanded(
                      child: Text(w.name, style: theme.textTheme.titleSmall)),
                  IconButton(
                    tooltip: 'Переименовать',
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _renameWorkout(w),
                  ),
                  IconButton(
                    tooltip: 'Удалить тренировку',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _deleteWorkout(w),
                  ),
                ],
              ),
            ),
            for (final (i, e) in w.items.indexed)
              ListTile(
                key: Key('ex-${w.name}-$i'),
                dense: true,
                title: Text(e.name),
                subtitle: Text(targetText(e)),
                onTap: () => _editExercise(w, i),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Выше',
                      icon: const Icon(Icons.arrow_upward, size: 20),
                      onPressed: i == 0 ? null : () => _move(w, i, -1),
                    ),
                    IconButton(
                      tooltip: 'Ниже',
                      icon: const Icon(Icons.arrow_downward, size: 20),
                      onPressed:
                          i == w.items.length - 1 ? null : () => _move(w, i, 1),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton.icon(
                key: Key('add-exercise-${w.name}'),
                onPressed: () => _editExercise(w, null),
                icon: const Icon(Icons.add),
                label: const Text('Упражнение'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetResult {
  const _SheetResult.save(ProgramExercise this.exercise) : delete = false;
  const _SheetResult.remove()
      : exercise = null,
        delete = true;
  final ProgramExercise? exercise;
  final bool delete;
}

class _ExerciseSheet extends StatefulWidget {
  const _ExerciseSheet({required this.workout, this.initial});
  final String workout;
  final ProgramExercise? initial;

  @override
  State<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends State<_ExerciseSheet> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _reps =
      TextEditingController(text: widget.initial?.repsTarget ?? '');
  late final _note = TextEditingController(text: widget.initial?.note ?? '');
  late var _type = widget.initial?.type ?? ExerciseType.strength;
  late var _sets = (widget.initial?.sets ?? 3).toDouble();
  late var _drop = widget.initial?.dropSet ?? false;
  late var _step = widget.initial?.weightStep ?? 2.5;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _reps.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите название');
      return;
    }
    final strength = _type == ExerciseType.strength;
    Navigator.of(context).pop(_SheetResult.save(ProgramExercise(
      workout: widget.workout,
      order: widget.initial?.order ?? 0,
      name: name,
      type: _type,
      sets: _sets.round().clamp(1, 99),
      repsTarget: _reps.text.trim(),
      dropSet: strength && _drop,
      weightStep: strength ? _step : 2.5,
      note: _note.text.trim(),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final strength = _type == ExerciseType.strength;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.initial == null ? 'Новое упражнение' : 'Упражнение',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              key: const Key('ex-name'),
              controller: _name,
              autofocus: widget.initial == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                  labelText: 'Название',
                  errorText: _error,
                  helperText: widget.initial == null
                      ? null
                      : 'История и графики привязаны к названию'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ExerciseType>(
              key: const Key('ex-type'),
              showSelectedIcon: false,
              segments: [
                for (final t in ExerciseType.values)
                  ButtonSegment(value: t, label: Text(_typeLabels[t]!)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            StepperField(
              key: const Key('stepper-sets'),
              label: 'Подходы',
              value: _sets,
              step: 1,
              integer: true,
              onChanged: (v) => setState(() => _sets = v < 1 ? 1 : v),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('ex-reps'),
              controller: _reps,
              decoration: InputDecoration(
                  labelText: switch (_type) {
                ExerciseType.strength => 'Повторы (например 8–10)',
                ExerciseType.timed => 'Секунды (например 30–45)',
                ExerciseType.cardio => 'Цель',
              }),
            ),
            if (strength) ...[
              const SizedBox(height: 12),
              StepperField(
                key: const Key('stepper-step'),
                label: 'Шаг веса, кг',
                value: _step,
                step: 0.5,
                onChanged: (v) => setState(() => _step = v <= 0 ? 0.5 : v),
              ),
              SwitchListTile(
                key: const Key('ex-drop'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Дроп-сет'),
                value: _drop,
                onChanged: (v) => setState(() => _drop = v),
              ),
            ],
            const SizedBox(height: 4),
            TextField(
              key: const Key('ex-note'),
              controller: _note,
              decoration: const InputDecoration(labelText: 'Заметка'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.initial != null)
                  TextButton(
                    key: const Key('ex-delete'),
                    onPressed: () =>
                        Navigator.of(context).pop(const _SheetResult.remove()),
                    child: const Text('Удалить'),
                  ),
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Отмена')),
                const SizedBox(width: 8),
                FilledButton(
                    key: const Key('ex-ok'),
                    onPressed: _submit,
                    child: const Text('Готово')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
