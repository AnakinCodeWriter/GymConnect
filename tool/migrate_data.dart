// GymConnect stored-value migration CLI (Phase 12, executes D3).
//
// A thin dart:io/REST shell over the pure modules:
//   lib/migration/migration_plan.dart - what is stale and what to write
//   lib/migration/migration_cli.dart  - argument parsing + configuration
//
// Run:  dart run tool/migrate_data.dart inspect
//       dart run tool/migrate_data.dart fix-all            (dry run)
//       dart run tool/migrate_data.dart fix-all --apply
// Full usage and required environment variables: see migrationUsage in
// lib/migration/migration_cli.dart (printed on any parse/config error).
//
// Safety:
//   * Read-only unless --apply is passed; --apply still asks for a typed
//     "yes" unless --yes is given.
//   * No document is ever deleted; only stored values are corrected.
//   * Only the signed-in user's own profile and leaderboard entry are
//     touched (the security rules enforce this too).
//   * personalRecords/bestLifts are written as whole map fields, so
//     exercise names never become Firestore field paths.
//   * Re-running after a successful apply reports "nothing to do".
//
// Output uses stdout/stderr writeln directly (a CLI's output IS its
// interface), consistent with tool/seed_data.dart.

import 'dart:convert';
import 'dart:io';

import 'package:gymconnect/migration/migration_cli.dart';
import 'package:gymconnect/migration/migration_plan.dart';

/// Must match LeaderboardService.anonymousDisplayName. The app-side
/// constant cannot be imported here (that file pulls in Firebase), so
/// test/migration_plan_test.dart asserts the two stay equal.
const String anonymousDisplayName = 'Anonymous';

Future<void> main(List<String> args) async {
  final command = parseMigrationArguments(args);
  switch (command) {
    case MigrationParseError(:final message):
      stderr.writeln('Error: $message\n');
      stdout.writeln(migrationUsage);
      exitCode = 64; // EX_USAGE
    case InspectCommand():
      await _withSession((s) => _run(s, null));
    case FixCommand():
      await _withSession((s) => _run(s, command));
  }
}

// ---- session (config + sign-in) ----

class _Session {
  final MigrationConfig config;
  final String uid;
  final String email;
  final String idToken;

  _Session(this.config, this.uid, this.email, this.idToken);
}

Future<void> _withSession(Future<void> Function(_Session) run) async {
  final (config, missing) = readMigrationConfig(Platform.environment);
  if (config == null) {
    stderr.writeln(
      'Error: missing required environment variable'
      '${missing.length == 1 ? '' : 's'}: ${missing.join(', ')}\n',
    );
    stdout.writeln(migrationUsage);
    exitCode = 78; // EX_CONFIG
    return;
  }

  final email = config.email ?? _promptLine('Email: ');
  final password = config.password ?? _promptLine('Password: ');

  stdout.writeln('\nSigning in to project "${config.projectId}"...');
  final Map<String, dynamic> auth;
  try {
    auth = await _jsonPostNoAuth(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword'
        '?key=${config.apiKey}',
      ),
      {'email': email, 'password': password, 'returnSecureToken': true},
    );
  } on Exception catch (e) {
    stderr.writeln('Sign-in failed: $e');
    stderr.writeln(
      'Check $envApiKey, the account credentials, and that email/password '
      'sign-in is enabled for the project.',
    );
    exitCode = 1;
    return;
  }

  final session = _Session(
    config,
    auth['localId'] as String,
    email,
    auth['idToken'] as String,
  );
  stdout.writeln(
    'Target: project=${config.projectId}  user=$email (${session.uid})\n',
  );
  await run(session);
}

String _promptLine(String prompt) {
  stdout.write(prompt);
  final line = stdin.readLineSync();
  if (line == null || line.trim().isEmpty) {
    stderr.writeln('Aborted: no input.');
    exit(1);
  }
  return line.trim();
}

bool _confirm(String action, {required bool assumeYes}) {
  if (assumeYes) return true;
  stdout.write('$action  Type "yes" to continue: ');
  final answer = stdin.readLineSync()?.trim().toLowerCase();
  if (answer == 'yes') return true;
  stdout.writeln('Aborted; nothing was changed.');
  return false;
}

// ---- the one flow (inspect = fix with cmd == null) ----

Future<void> _run(_Session s, FixCommand? cmd) async {
  stdout.writeln('Reading workout history...');
  final history = await _loadHistory(s);
  final recomputed = bestE1RmPerExerciseAcross(history);
  stdout.writeln(
    '  ${history.length} workout(s); ${recomputed.length} exercise(s) with '
    'eligible sets.\n',
  );

  final profile = await _getDocument(s, ['users', s.uid]);
  if (profile == null) {
    stderr.writeln(
      'No profile document at users/${s.uid}. Nothing to migrate; sign in '
      'with the account that owns the data.',
    );
    exitCode = 1;
    return;
  }

  final recordsPlan = planPersonalRecords(
    stored: _numberMap(profile['personalRecords']),
    recomputed: recomputed,
  );
  _reportRecords(recordsPlan);

  final gymId = profile['gymId'] as String? ?? '';
  LeaderboardPlan? leaderboardPlan;
  if (gymId.isEmpty) {
    stdout.writeln('\nLeaderboard: profile has no gymId - nothing to check.');
  } else {
    final entry = await _getDocument(s, ['gyms', gymId, 'leaderboard', s.uid]);
    if (entry == null) {
      stdout.writeln(
        '\nLeaderboard: no entry in gym "$gymId" yet - nothing to check.',
      );
    } else {
      leaderboardPlan = planLeaderboard(
        storedLifts: _numberMap(entry['bestLifts']),
        recomputed: recomputed,
        isAnonymous: entry['isAnonymous'] == true,
        storedDisplayName: entry['displayName'] as String? ?? '',
        safeDisplayName: anonymousDisplayName,
      );
      _reportLeaderboard(leaderboardPlan, gymId);
    }
  }

  if (cmd == null) {
    stdout.writeln(
      '\nRead-only inspection complete. Correct these with:\n'
      '  dart run tool/migrate_data.dart fix-all --apply',
    );
    return;
  }

  final willWriteRecords = cmd.touchesRecords && recordsPlan.hasChanges;
  final willWriteLeaderboard =
      cmd.touchesLeaderboard && (leaderboardPlan?.hasChanges ?? false);

  if (!willWriteRecords && !willWriteLeaderboard) {
    stdout.writeln('\nNothing to do: stored values already match.');
    return;
  }

  if (!cmd.apply) {
    stdout.writeln(
      '\nDry run: nothing was written. Re-run with --apply to correct '
      '${[if (willWriteRecords) 'personal records', if (willWriteLeaderboard) 'leaderboard values'].join(' and ')}.',
    );
    return;
  }

  if (!_confirm(
    '\nThis CORRECTS stored values in project "${s.config.projectId}" for '
    '${s.email}. Nothing is deleted.',
    assumeYes: cmd.assumeYes,
  )) {
    return;
  }

  if (willWriteRecords) {
    await _patchDocument(
      s,
      ['users', s.uid],
      fields: {'personalRecords': _encodeNumberMap(recordsPlan.mergedRecords)},
      updateMask: const ['personalRecords'],
    );
    stdout.writeln(
      'Updated personalRecords: ${recordsPlan.corrections.length} '
      'correction(s) written.',
    );
  }

  if (willWriteLeaderboard) {
    final plan = leaderboardPlan!;
    final fields = <String, Object>{};
    if (plan.corrections.isNotEmpty) {
      fields['bestLifts'] = _encodeNumberMap(plan.mergedLifts);
    }
    if (plan.anonymityNameLeak) {
      fields['displayName'] = {'stringValue': plan.safeDisplayName};
    }
    await _patchDocument(
      s,
      ['gyms', gymId, 'leaderboard', s.uid],
      fields: fields,
      updateMask: fields.keys.toList(),
    );
    stdout.writeln(
      'Updated leaderboard entry: ${plan.corrections.length} lift '
      'correction(s)'
      '${plan.anonymityNameLeak ? ', display name replaced with "${plan.safeDisplayName}"' : ''}.',
    );
  }

  stdout.writeln(
    '\nDone. Re-run "inspect" to confirm nothing remains (this tool is '
    'idempotent). A running app shows corrected values after '
    'pull-to-refresh or restart.',
  );
}

// ---- reporting ----

void _reportRecords(PersonalRecordsPlan plan) {
  stdout.writeln('Personal records (users/{uid}.personalRecords):');
  if (plan.stored.isEmpty) {
    stdout.writeln('  none stored.');
    return;
  }
  stdout.writeln('  ${plan.unchanged} already correct');
  stdout.writeln(
    '  ${plan.corrections.length} to correct '
    '(${plan.loweredCount} lowered, ${plan.raisedCount} raised)',
  );
  for (final c in plan.corrections) {
    stdout.writeln(
      '    ${c.exercise}: ${_kg(c.storedKg)} -> ${_kg(c.correctedKg)} kg',
    );
  }
  if (plan.orphans.isNotEmpty) {
    stdout.writeln(
      '  ${plan.orphans.length} record(s) with no logged history - LEFT '
      'UNTOUCHED:',
    );
    for (final o in plan.orphans) {
      stdout.writeln('    ${o.exercise}: ${_kg(o.storedKg)} kg');
    }
  }
}

void _reportLeaderboard(LeaderboardPlan plan, String gymId) {
  stdout.writeln('\nLeaderboard entry (gyms/$gymId/leaderboard/{uid}):');
  stdout.writeln('  ${plan.unchanged} lift(s) already correct');
  stdout.writeln(
    '  ${plan.corrections.length} lift(s) to correct '
    '(${plan.loweredCount} lowered, ${plan.raisedCount} raised)',
  );
  for (final c in plan.corrections) {
    stdout.writeln(
      '    ${c.exercise}: ${_kg(c.storedKg)} -> ${_kg(c.correctedKg)} kg',
    );
  }
  if (plan.orphans.isNotEmpty) {
    stdout.writeln(
      '  ${plan.orphans.length} lift(s) with no logged history - LEFT '
      'UNTOUCHED.',
    );
  }
  if (plan.anonymityNameLeak) {
    stdout.writeln(
      '  ANONYMITY: entry is anonymous but stores the readable name '
      '"${plan.storedDisplayName}" - will be replaced with '
      '"${plan.safeDisplayName}".',
    );
  } else if (plan.isAnonymous) {
    stdout.writeln('  Anonymity: entry already stores the safe display name.');
  }
}

String _kg(double v) => v.toStringAsFixed(2);

// ---- Firestore REST helpers ----

Uri _documentUri(_Session s, List<String> path, {List<String>? updateMask}) {
  final base =
      'https://firestore.googleapis.com/v1/projects/${s.config.projectId}'
      '/databases/(default)/documents/${path.join('/')}';
  if (updateMask == null) return Uri.parse(base);
  // Repeated query parameter, one entry per field path.
  final query = updateMask
      .map((f) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(f)}')
      .join('&');
  return Uri.parse('$base?$query');
}

Future<List<StoredWorkout>> _loadHistory(_Session s) async {
  final workouts = <StoredWorkout>[];
  String? pageToken;
  do {
    final uri = _documentUri(s, [
      'users',
      s.uid,
      'workouts',
    ]).replace(queryParameters: {'pageSize': '300', 'pageToken': ?pageToken});
    final body = await _jsonRequest('GET', uri, s.idToken, null);
    for (final doc in (body['documents'] as List? ?? const [])) {
      final fields =
          (doc as Map<String, dynamic>)['fields'] as Map<String, dynamic>? ??
          const {};
      workouts.add(_decodeWorkout(fields));
    }
    pageToken = body['nextPageToken'] as String?;
  } while (pageToken != null);
  return workouts;
}

/// Decodes the exercises/sets a recomputation needs. Malformed entries are
/// skipped exactly as the app skips malformed documents - a set that cannot
/// be read contributes nothing rather than corrupting a corrected value.
StoredWorkout _decodeWorkout(Map<String, dynamic> fields) {
  final exercises = <StoredExercise>[];
  for (final raw in _arrayValues(fields['exercises'])) {
    final exFields = _mapFields(raw);
    final name = exFields['name']?['stringValue'] as String?;
    if (name == null) continue;
    final sets = <StoredSet>[];
    for (final rawSet in _arrayValues(exFields['sets'])) {
      final setFields = _mapFields(rawSet);
      final weight = _toDouble(setFields['weight']);
      final reps = _toInt(setFields['reps']);
      if (weight == null || reps == null) continue;
      sets.add(
        StoredSet(
          weight: weight,
          reps: reps,
          isWarmup: setFields['isWarmup']?['booleanValue'] == true,
        ),
      );
    }
    exercises.add(StoredExercise(name: name, sets: sets));
  }
  return StoredWorkout(exercises: exercises);
}

List<dynamic> _arrayValues(Object? field) {
  if (field is! Map<String, dynamic>) return const [];
  final array = field['arrayValue'];
  if (array is! Map<String, dynamic>) return const [];
  return array['values'] as List? ?? const [];
}

Map<String, dynamic> _mapFields(Object? value) {
  if (value is! Map<String, dynamic>) return const {};
  final map = value['mapValue'];
  if (map is! Map<String, dynamic>) return const {};
  return map['fields'] as Map<String, dynamic>? ?? const {};
}

double? _toDouble(Object? field) {
  if (field is! Map<String, dynamic>) return null;
  final d = field['doubleValue'];
  if (d is num) return d.toDouble();
  final i = field['integerValue'];
  if (i is String) return double.tryParse(i);
  if (i is num) return i.toDouble();
  return null;
}

int? _toInt(Object? field) {
  final d = _toDouble(field);
  return d?.round();
}

/// Reads a document's decoded top-level fields, or null when absent.
Future<Map<String, dynamic>?> _getDocument(
  _Session s,
  List<String> path,
) async {
  final Map<String, dynamic> body;
  try {
    body = await _jsonRequest('GET', _documentUri(s, path), s.idToken, null);
  } on _HttpFailure catch (e) {
    if (e.statusCode == 404) return null;
    rethrow;
  }
  final fields = body['fields'] as Map<String, dynamic>? ?? const {};
  return {for (final e in fields.entries) e.key: _decodeScalarOrMap(e.value)};
}

/// Decodes the shapes this tool reads: strings, booleans, numbers and
/// one level of number map (personalRecords / bestLifts).
Object? _decodeScalarOrMap(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  if (value.containsKey('stringValue')) return value['stringValue'];
  if (value.containsKey('booleanValue')) return value['booleanValue'];
  if (value.containsKey('doubleValue') || value.containsKey('integerValue')) {
    return _toDouble(value);
  }
  if (value.containsKey('mapValue')) {
    final fields = _mapFields(value);
    return {for (final e in fields.entries) e.key: _toDouble(e.value)};
  }
  return null;
}

Map<String, double> _numberMap(Object? decoded) {
  if (decoded is! Map) return const {};
  final out = <String, double>{};
  for (final e in decoded.entries) {
    final v = e.value;
    if (e.key is String && v is num) out[e.key as String] = v.toDouble();
  }
  return out;
}

Map<String, Object> _encodeNumberMap(Map<String, double> values) => {
  'mapValue': {
    'fields': {
      for (final e in values.entries) e.key: {'doubleValue': e.value},
    },
  },
};

Future<void> _patchDocument(
  _Session s,
  List<String> path, {
  required Map<String, Object> fields,
  required List<String> updateMask,
}) async {
  await _jsonRequest(
    'PATCH',
    _documentUri(s, path, updateMask: updateMask),
    s.idToken,
    {'fields': fields},
  );
}

class _HttpFailure implements Exception {
  final int statusCode;
  final String message;

  _HttpFailure(this.statusCode, this.message);

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> _jsonRequest(
  String method,
  Uri uri,
  String token,
  Map<String, dynamic>? body,
) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, uri);
    req.headers.set('Authorization', 'Bearer $token');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final raw = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _HttpFailure(
        res.statusCode,
        '$method $uri -> HTTP ${res.statusCode}: $raw',
      );
    }
    return raw.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> _jsonPostNoAuth(
  Uri uri,
  Map<String, dynamic> body,
) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    final raw = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw _HttpFailure(res.statusCode, 'HTTP ${res.statusCode}: $raw');
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}
