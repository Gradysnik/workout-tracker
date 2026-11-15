import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/domain/exercise_key.dart';

void main() {
  test('сжимает пробелы и переносы строк, приводит к нижнему регистру', () {
    expect(exerciseKey('  Тяга верхнего блока \nк груди  (широкий) '),
        'тяга верхнего блока к груди (широкий)');
  });
  test('регистр и двойные пробелы не создают новое упражнение', () {
    expect(exerciseKey('FACE pulls'), exerciseKey('Face  Pulls'));
  });
}
