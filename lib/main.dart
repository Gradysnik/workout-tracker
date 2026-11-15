import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const WorkoutTrackerApp());
}

class WorkoutTrackerApp extends StatelessWidget {
  const WorkoutTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Workout Tracker',
      home: Scaffold(body: Center(child: Text('Workout Tracker'))),
    );
  }
}
