library;

import 'dart:math';

enum PlateauStatus { progressing, plateau, regressing, insufficientData }

class PlateauResult {
  final PlateauStatus status;

  /// slope of the weighted regression line in kg per session.
  /// positive = progressing, negative = regressing, near-zero = plateau.
  final double slope;

  const PlateauResult({required this.status, required this.slope});
}

class PlateauDetector {
  /// minimum sessions before analysis runs. 5 gives the regression
  /// enough data points to be statistically meaningful.
  static const int minSessions = 5;

  // Thresholds are fractions of the weighted mean e1RM (0.25% per session).
  // Using a relative value means the same rule works for a lifter whose
  // best squat is 60 kg and one whose best is 200 kg.
  static const double progressThreshold = 0.0025;
  static const double regressThreshold = -0.0025;

  /// exponential decay factor applied per session.
  /// 0.85 means each session further back in time is 15% less influential,
  /// so a recent stall outweighs older progress (and vice-versa).
  static const double _decay = 0.85;

  /// Analyse a list of (date, best-e1RM) pairs for a single exercise using
  /// Weighted Least Squares regression with exponential recency decay.
  ///
  /// OLS treats a session from six months ago identically to last Tuesday.
  /// WLS corrects this: the most recent session gets weight 1.0, each
  /// earlier session is multiplied by [_decay], so recent trends dominate.
  ///
  /// The list does not need to be sorted beforehand.
  static PlateauResult analyse(List<(DateTime, double)> sessions) {
    if (sessions.length < minSessions) {
      return const PlateauResult(
          status: PlateauStatus.insufficientData, slope: 0);
    }

    // Sort oldest to newest so index 0 is the earliest session.
    final sorted = [...sessions]..sort((a, b) => a.$1.compareTo(b.$1));
    final n = sorted.length;

    // w_i = decay^(n-1-i): newest session (i=n-1) gets weight 1.0,
    // each earlier session is discounted by the decay factor.
    double sumW = 0, sumWX = 0, sumWY = 0, sumWXX = 0, sumWXY = 0;

    for (int i = 0; i < n; i++) {
      final w = pow(_decay, n - 1 - i).toDouble();
      final x = i.toDouble();
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

    // Normalise the slope by the weighted mean e1RM so the threshold is
    // scale-invariant: 0.0025 means "0.25% change per session".
    final weightedMeanY = sumWY / sumW;
    final normalizedSlope =
        weightedMeanY > 0 ? slope / weightedMeanY : slope;

    final status = normalizedSlope > progressThreshold
        ? PlateauStatus.progressing
        : normalizedSlope < regressThreshold
            ? PlateauStatus.regressing
            : PlateauStatus.plateau;

    return PlateauResult(status: status, slope: slope);
  }
}
