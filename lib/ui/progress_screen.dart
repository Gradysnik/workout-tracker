import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/exercise_key.dart';
import '../domain/models.dart';
import '../domain/progress.dart';
import '../providers.dart';
import 'format.dart';

/// Цвет линии графика не зависит от системной палитры.
const chartColor = Color(0xFF5B9DFF);

const _metricNames = {
  Metric.maxWeight: 'Макс. вес',
  Metric.volume: 'Объём',
  Metric.reps: 'Повторы',
  Metric.seconds: 'Секунды',
  Metric.kcal: 'Ккал',
};

/// Тип упражнения по его записям — для упражнений, которых уже нет в программе.
ExerciseType inferType(List<JournalRow> rows) {
  if (rows.any((r) => r.weight != null || r.reps != null)) {
    return ExerciseType.strength;
  }
  if (rows.any((r) => r.seconds != null)) return ExerciseType.timed;
  return rows.isEmpty ? ExerciseType.strength : ExerciseType.cardio;
}

typedef _History = ({List<JournalRow> rows, ExerciseType type});

final _historyProvider =
    FutureProvider.autoDispose.family<_History, String>((ref, key) async {
  ref.watch(revisionProvider);
  final rows = await ref.watch(journalStoreProvider).historyOf(key);
  final program = await ref.watch(programStoreProvider).program();
  final inProgram = program.where((e) => exerciseKey(e.name) == key);
  return (
    rows: rows,
    type: inProgram.isNotEmpty ? inProgram.first.type : inferType(rows),
  );
});

/// График и история одного упражнения.
class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key, required this.exerciseName});
  final String exerciseName;

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  Metric? _metric;

  @override
  Widget build(BuildContext context) {
    final history =
        ref.watch(_historyProvider(exerciseKey(widget.exerciseName)));
    return Scaffold(
      appBar: AppBar(title: const Text('Прогресс')),
      body: SafeArea(
        child: switch (history) {
          AsyncValue(:final value?) => _body(context, value),
          AsyncValue(:final error?) =>
            Center(child: Text('Не удалось открыть данные: $error')),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _body(BuildContext context, _History history) {
    final theme = Theme.of(context);
    final rows = history.rows;
    final name = rows.isEmpty ? widget.exerciseName : rows.last.exercise;
    final byDate = <DateTime, List<JournalRow>>{};
    for (final r in rows) {
      byDate.putIfAbsent(r.date, () => []).add(r);
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
    final metrics = metricsFor(history.type);
    final metric = metrics.contains(_metric) ? _metric! : metrics.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        Text(name, style: theme.textTheme.titleLarge),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: Text('Пока нет записей')),
          )
        else ...[
          Text(
              'с ${formatShortDate(dates.last)} · '
              '${plural(dates.length, 'тренировка', 'тренировки', 'тренировок')}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final m in metrics)
                ChoiceChip(
                  label: Text(_metricNames[m]!),
                  selected: m == metric,
                  onSelected: (_) => setState(() => _metric = m),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(height: 200, child: _chart(context, rows, metric)),
          const SizedBox(height: 12),
          for (final d in dates)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                dense: true,
                title: Text(formatShortDate(d)),
                subtitle: Text(formatSets(byDate[d]!)),
              ),
            ),
        ],
      ],
    );
  }

  Widget _chart(BuildContext context, List<JournalRow> rows, Metric metric) {
    final theme = Theme.of(context);
    final series = progressSeries(rows, metric);
    if (series.isEmpty) {
      return const Center(child: Text('Нет данных для этой метрики'));
    }
    final labelStyle = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final values = series.map((p) => p.value);
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final pad = hi == lo ? (hi == 0 ? 1.0 : hi * 0.1) : (hi - lo) * 0.15;
    return LineChart(LineChartData(
      minX: 0,
      maxX: series.length > 1 ? (series.length - 1).toDouble() : 1,
      minY: lo - pad,
      maxY: hi + pad,
      gridData: FlGridData(
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: theme.colorScheme.outlineVariant, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        bottomTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            getTitlesWidget: (v, meta) => v == meta.min || v == meta.max
                ? const SizedBox.shrink()
                : Text(formatNumber(v.roundToDouble()), style: labelStyle),
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                  '${formatShortDate(series[s.x.round()].date)}\n'
                  '${formatNumber(s.y)}',
                  theme.textTheme.labelMedium!
                      .copyWith(color: theme.colorScheme.onInverseSurface)),
          ],
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (final (i, p) in series.indexed) FlSpot(i.toDouble(), p.value)
          ],
          color: chartColor,
          barWidth: 3,
          dotData: FlDotData(show: series.length <= 12),
        ),
      ],
    ));
  }
}
