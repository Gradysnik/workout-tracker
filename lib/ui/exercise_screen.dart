import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/models.dart';

/// Ввод подходов упражнения [exercise] за дату [date].
class ExerciseScreen extends ConsumerWidget {
  const ExerciseScreen({super.key, required this.exercise, required this.date});
  final ProgramExercise exercise;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Scaffold(appBar: AppBar(title: Text(exercise.name)));
}
