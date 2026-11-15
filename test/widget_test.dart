import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workout_tracker/app.dart';

import 'ui/harness.dart';

void main() {
  testWidgets('оболочка: три вкладки, открыта «Сегодня»', (t) async {
    final h = Harness();
    await h.seed();
    await h.pump(t, const HomeShell());
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.text('История'), findsOneWidget);
    expect(find.text('Программа'), findsOneWidget);
    expect(find.text('Тяга верхнего блока'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}
