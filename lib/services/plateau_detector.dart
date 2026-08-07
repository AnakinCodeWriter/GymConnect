import 'dart:math';

enum PlateauStatus { progressing, plateau, regressing, insufficientData }

class PlateauResult {
  final PlateauStatus status;

  final double slope; // kg per day

  const PlateauResult({required this.status, required this.slope});
}

class PlateauDetector {
  static const int minSessions = 5;

  // Thresholds are fractions of the weighted mean e1RM per day (0.1%/day, ~0.7%/week).
  // Scale-invariant: same sensitivity for a 60 kg lifter and a 200 kg lifter.
  static const double progressThreshold = 0.001;
  static const double regressThreshold = -0.001;

  static const double _decay = 0.85;

  // WLS regression with exponential recency decay. Input does not need to be sorted.
  static PlateauResult analyse(List<(DateTime, double)> sessions) {
    if (sessions.length < minSessions) {
      return const PlateauResult(
        status: PlateauStatus.insufficientData,
        slope: 0,
      );
    }

    // Sort oldest to newest so index 0 is the earliest session.
    final sorted = [...sessions]..sort((a, b) => a.$1.compareTo(b.$1));
    final n = sorted.length;

    // w_i = decay^(n-1-i): newest session (i=n-1) gets weight 1.0,
    // each earlier session is discounted by the decay factor.
    double sumW = 0, sumWX = 0, sumWY = 0, sumWXX = 0, sumWXY = 0;

    for (int i = 0; i < n; i++) {
      final w = pow(_decay, n - 1 - i).toDouble();
      final x = sorted[i].$1.difference(sorted.first.$1).inDays.toDouble();
      final y = sorted[i].$2;
      sumW += w;
      sumWX += w * x;
      sumWY += w * y;
      sumWXX += w * x * x;
      sumWXY += w * x * y;
    }

    // WLS normal equations: b = (S_w*S_wxy - S_wx*S_wy) / (S_w*S_wxx - S_wx^2)
    final denominator = sumW * sumWXX - sumWX * sumWX;
    if (denominator == 0) {
      return const PlateauResult(status: PlateauStatus.plateau, slope: 0);
    }

    final slope = (sumW * sumWXY - sumWX * sumWY) / denominator;

    // Normalise by the weighted mean e1RM so the threshold is scale-invariant.
    final weightedMeanY = sumWY / sumW;
    final normalizedSlope = weightedMeanY > 0 ? slope / weightedMeanY : slope;

    final status = normalizedSlope > progressThreshold
        ? PlateauStatus.progressing
        : normalizedSlope < regressThreshold
        ? PlateauStatus.regressing
        : PlateauStatus.plateau;

    return PlateauResult(status: status, slope: slope);
  }
}
