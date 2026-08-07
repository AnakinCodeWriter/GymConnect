import 'package:firebase_core/firebase_core.dart';

/// Stable application-level failure categories for data access (Phase 4).
/// Distinct from analytics insufficiency (lib/models/analytics.dart):
/// "no workouts exist" is a successful empty result, "workouts could not be
/// loaded" is a [DataFailure], and "not enough sessions for a trend" is an
/// analytics-domain result.
enum DataFailureKind {
  /// No signed-in user; user-specific paths were never constructed.
  unauthenticated,
  permissionDenied,

  /// Backend unreachable (offline, service unavailable).
  unavailable,
  timeout,
  notFound,

  /// Stored data was structurally unusable for the operation.
  invalidData,

  /// Conservative fallback - not every failure can be identified.
  unknown,
}

/// One document that could not be parsed during a collection load. Loads
/// return valid records plus these typed warnings - malformed documents are
/// never silently discarded (see docs/DECISIONS.md, Phase 4).
class SkippedDocument {
  final String documentId;

  /// The original parse error, retained for debugging. Callers must not
  /// parse it - it is not part of the API surface.
  final Object cause;

  const SkippedDocument(this.documentId, this.cause);
}

/// Outcome of a data-access operation. An empty list is a [DataSuccess];
/// failure is always typed.
sealed class DataResult<T> {
  const DataResult();

  bool get isSuccess => this is DataSuccess<T>;

  T? get dataOrNull => switch (this) {
    DataSuccess<T>(:final data) => data,
    DataFailure<T>() => null,
  };
}

class DataSuccess<T> extends DataResult<T> {
  final T data;

  /// Documents skipped as unreadable during a collection load; empty for
  /// single-document and write operations.
  final List<SkippedDocument> skipped;

  const DataSuccess(this.data, {this.skipped = const []});
}

class DataFailure<T> extends DataResult<T> {
  final DataFailureKind kind;

  /// Original error for debugging/logging only - never parsed by callers
  /// and never shown raw to users.
  final Object? cause;

  const DataFailure(this.kind, [this.cause]);
}

/// Maps an arbitrary error to a stable failure category. Uses Firebase
/// error codes where available; anything unrecognised falls back to
/// [DataFailureKind.unknown].
DataFailureKind failureKindFor(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return DataFailureKind.permissionDenied;
      case 'unauthenticated':
        return DataFailureKind.unauthenticated;
      case 'unavailable':
      case 'network-request-failed':
        return DataFailureKind.unavailable;
      case 'deadline-exceeded':
        return DataFailureKind.timeout;
      case 'not-found':
        return DataFailureKind.notFound;
      case 'invalid-argument':
      case 'data-loss':
        return DataFailureKind.invalidData;
    }
    return DataFailureKind.unknown;
  }
  if (error is FormatException || error is TypeError) {
    return DataFailureKind.invalidData;
  }
  return DataFailureKind.unknown;
}
