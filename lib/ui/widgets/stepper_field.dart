import 'package:material_ui/material_ui.dart';

import '../format.dart';

/// Крупное поле «минус — число — плюс». Касание по числу открывает точный ввод.
class StepperField extends StatelessWidget {
  const StepperField({
    super.key,
    required this.value,
    required this.step,
    required this.label,
    required this.onChanged,
    this.integer = false,
  });

  final double value;
  final double step;
  final String label;
  final ValueChanged<double> onChanged;
  final bool integer;

  void _set(double v) {
    if (v < 0) v = 0;
    onChanged(integer ? v.roundToDouble() : v);
  }

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: formatNumber(value));
    controller.selection =
        TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
    final parsed =
        double.tryParse((text ?? '').trim().replaceAll(',', '.'));
    if (parsed != null && parsed.isFinite) _set(parsed);
  }

  Widget _button(BuildContext context, IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(width: 64, height: 60, child: Icon(icon, size: 28)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (key is ValueKey<String>) ? (key! as ValueKey<String>).value : 'stepper';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            _button(context, Icons.remove, () => _set(value - step)),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _edit(context),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatNumber(value),
                        key: Key('$name-value'),
                        style: theme.textTheme.headlineMedium),
                    Text(label,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            _button(context, Icons.add, () => _set(value + step)),
          ],
        ),
      ),
    );
  }
}
