library;

enum PlateauStatus { progressing, plateau, regressing, insufficientData }

class PlateauResult {
  final PlateauStatus status;

  /// slope of the regression line in kg per session
  /// this only really means anything when we have enough data points
  final double slope;

  const PlateauResult({required this.status, required this.slope});
}

class PlateauDetector {
  /// minimum number of sessions needed before we try to analyse anything
  static const int minSessions = 3;

  /// if the slope is above this we consider the user to be progressing
  static const double progressThreshold = 0.5;

  /// if the slope is below this we consider the user to be regressing
  static const double regressThreshold = -0.5;

  /// analyse a list of (date, best-1RM) pairs for a single exercise
  ///
  /// notes:
  /// - the list doesn’t need to be sorted beforehand.
  /// - ideally there should be one value per session/day, but duplicates won’t break anything
  static PlateauResult analyse(List<(DateTime, double)> sessions) {
    if (sessions.length < minSessions) {
      return const PlateauResult(
          status: PlateauStatus.insufficientData, slope: 0);
    }

    // sort sessions from oldest to newest so the x-axis reflects time progression
    final sorted = [...sessions]..sort((a, b) => a.$1.compareTo(b.$1));

    final n = sorted.length.toDouble();
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;

    for (int i = 0; i < sorted.length; i++) {
      final x = i.toDouble(); // session index
      final y = sorted[i].$2; // best 1RM for that session
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }

    final denominator = n * sumX2 - sumX * sumX;

    // if the denominator is zero, we can't compute a meaningful slope.
    // this would happen if all x values are effectively the same.
    if (denominator == 0) {
      return const PlateauResult(status: PlateauStatus.plateau, slope: 0);
    }

    final slope = (n * sumXY - sumX * sumY) / denominator;

    // simple classification based on slope thresholds.
    final status = slope > progressThreshold
        ? PlateauStatus.progressing
        : slope < regressThreshold
            ? PlateauStatus.regressing
            : PlateauStatus.plateau;

    return PlateauResult(status: status, slope: slope);
  }
}