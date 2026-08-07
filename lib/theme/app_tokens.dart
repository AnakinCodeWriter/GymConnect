import 'package:flutter/widgets.dart';

// Lightweight shared layout tokens (Phase 5). New/shared widgets use these;
// migrating every existing literal padding is intentionally deferred
// (docs/DECISIONS.md).

abstract final class Insets {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Standard page content padding.
  static const EdgeInsets page = EdgeInsets.all(lg);
}

abstract final class Corners {
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 12;
}
