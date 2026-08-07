import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/analytics.dart';
import '../utils/dates.dart';
import '../utils/units.dart';

/// Best-estimated-1RM-per-session line chart (extracted from the Progress
/// screen in Phase 11; rendering behaviour unchanged). Renders nothing with
/// fewer than 2 sessions - a single point is not a trend.
class E1rmChart extends StatelessWidget {
  /// Ascending per-day sessions for one exercise (kg values).
  final List<ExerciseSession> sessions;

  /// 'kg' or 'lbs' display unit.
  final String unit;

  const E1rmChart({super.key, required this.sessions, required this.unit});

  @override
  Widget build(BuildContext context) {
    if (sessions.length < 2) return const SizedBox.shrink();

    // Build fl_chart spots: x = session index, y = best 1RM in display unit.
    final spots = [
      for (int i = 0; i < sessions.length; i++)
        FlSpot(i.toDouble(), kgToDisplayUnit(sessions[i].bestE1RmKg, unit)),
    ];

    final e1rmValues = sessions
        .map((s) => kgToDisplayUnit(s.bestE1RmKg, unit))
        .toList();
    final minY = (e1rmValues.reduce((a, b) => a < b ? a : b) - 5)
        .clamp(0, double.infinity)
        .toDouble();
    final maxY = e1rmValues.reduce((a, b) => a > b ? a : b) + 5;

    // How often to show an x-axis label: aim for at most 4 labels.
    final labelStep = (sessions.length / 4).ceil().clamp(1, sessions.length);

    final lineColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Y-axis title, rotated 90°.
              RotatedBox(
                quarterTurns: 3,
                child: Text(
                  'Est. 1RM ($unit)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SizedBox(
                  height: 180,
                  child: LineChart(
                    LineChartData(
                      minY: minY,
                      maxY: maxY,
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: false,
                          color: lineColor,
                          barWidth: 2,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                              radius: 4,
                              color: lineColor,
                              strokeWidth: 0,
                              strokeColor: Colors.transparent,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: lineColor.withAlpha(25),
                          ),
                        ),
                      ],
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= sessions.length) {
                                return const SizedBox.shrink();
                              }
                              if (i != 0 &&
                                  i != sessions.length - 1 &&
                                  i % labelStep != 0) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  formatDayMonth(sessions[i].day),
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            getTitlesWidget: (value, meta) {
                              if (value != meta.min &&
                                  value != meta.max &&
                                  value !=
                                      ((meta.min + meta.max) / 2)
                                          .roundToDouble()) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                '${value.toStringAsFixed(0)}$unit',
                                style: const TextStyle(fontSize: 10),
                              );
                            },
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: (maxY - minY) / 4,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: Colors.grey.withAlpha(50),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // X-axis title.
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Session Date',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}
