import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workout_tracker/ui/widgets/stepper_field.dart';

void main() {
  Future<List<double>> pump(WidgetTester t, {double value = 60, double step = 2.5, bool integer = false}) async {
    final changes = <double>[];
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => StepperField(
                    key: const Key('f'), value: value, step: step, label: 'кг', integer: integer,
                    onChanged: (v) => setState(() { value = v; changes.add(v); }))))));
    return changes;
  }

  testWidgets('плюс прибавляет шаг, минус вычитает', (t) async {
    final changes = await pump(t);
    await t.tap(find.byIcon(Icons.add));
    await t.pump();
    expect(find.text('62,5'), findsOneWidget);
    await t.tap(find.byIcon(Icons.remove));
    await t.pump();
    await t.tap(find.byIcon(Icons.remove));
    await t.pump();
    expect(changes, [62.5, 60, 57.5]);
  });

  testWidgets('не уходит ниже нуля', (t) async {
    final changes = await pump(t, value: 1);
    await t.tap(find.byIcon(Icons.remove));
    await t.pump();
    expect(changes, [0]);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('касание по числу открывает точный ввод, запятая понимается', (t) async {
    final changes = await pump(t);
    await t.tap(find.text('60'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '7,5');
    await t.tap(find.text('ОК'));
    await t.pumpAndSettle();
    expect(changes, [7.5]);
    expect(find.text('7,5'), findsOneWidget);
  });

  testWidgets('целое поле округляет ввод, мусор игнорируется', (t) async {
    final changes = await pump(t, value: 10, step: 1, integer: true);
    await t.tap(find.text('10'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '12.6');
    await t.tap(find.text('ОК'));
    await t.pumpAndSettle();
    await t.tap(find.text('13'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'абв');
    await t.tap(find.text('ОК'));
    await t.pumpAndSettle();
    expect(changes, [13]);
  });

  testWidgets('кнопки не меньше 48×48', (t) async {
    await pump(t);
    for (final icon in [Icons.add, Icons.remove]) {
      final size = t.getSize(find.ancestor(of: find.byIcon(icon), matching: find.byType(InkWell)).first);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });
}
