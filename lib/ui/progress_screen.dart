import 'package:material_ui/material_ui.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, required this.exerciseName});
  final String exerciseName;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(exerciseName)));
}
