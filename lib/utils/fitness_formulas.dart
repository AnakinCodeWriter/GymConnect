// Epley formula with rep cap at 10 to avoid overestimation at high volumes.
double estimatedOneRepMax(double weight, int reps) {
  final r = reps.clamp(1, 10);
  return weight * (1 + r / 30);
}
