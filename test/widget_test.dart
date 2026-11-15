import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/main.dart';

void main() {
  testWidgets('приложение запускается', (tester) async {
    await tester.pumpWidget(const WorkoutTrackerApp());
    expect(find.text('Workout Tracker'), findsOneWidget);
  });
}
