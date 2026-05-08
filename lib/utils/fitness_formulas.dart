/// Strength training formula utilities used across the app.
///
/// The Epley formula (weight × (1 + reps/30)) is a widely cited e1RM
/// estimator but overestimates significantly above ~12 reps because the
/// linear approximation no longer holds at high volumes. Capping the rep
/// input at 10 produces conservative, more accurate estimates for
/// high-rep sets while leaving low-rep results essentially unchanged.
double estimatedOneRepMax(double weight, int reps) {
  final r = reps.clamp(1, 10);
  return weight * (1 + r / 30);
}
