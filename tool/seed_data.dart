// GymConnect demo-data CLI (Phase 9 rewrite).
//
// A thin dart:io shell over the pure demo modules:
//   lib/demo/demo_fixtures.dart  - deterministic scenario generation
//   lib/demo/demo_plan.dart      - tagging + cleanup selection rules
//   lib/demo/demo_cli.dart       - argument parsing + configuration rules
//
// Run:  dart run tool/seed_data.dart list-scenarios
//       dart run tool/seed_data.dart seed --scenario progressing
//       dart run tool/seed_data.dart cleanup --all --dry-run
// Full usage and required environment variables: see cliUsage in
// lib/demo/demo_cli.dart (printed on any parse/config error).
//
// Safety: no hard-coded keys or project ids (configuration comes from the
// environment); the target project, user and counts are always displayed;
// writes and deletes require typing "yes" unless --yes is passed; only
// documents tagged isDemo:true are ever deleted.
//
// Output uses stdout/stderr writeln directly (a CLI's output IS its
// interface) - this also removed the pre-Phase-9 avoid_print infos.

import 'dart:convert';
import 'dart:io';

import 'package:gymconnect/demo/demo_cli.dart';
import 'package:gymconnect/demo/demo_fixtures.dart';
import 'package:gymconnect/demo/demo_plan.dart';

Future<void> main(List<String> args) async {
  final command = parseCliArguments(args);
  switch (command) {
    case CliParseError(:final message):
      stderr.writeln('Error: $message\n');
      stdout.writeln(cliUsage);
      exitCode = 64; // EX_USAGE
    case ListScenariosCommand():
      _listScenarios();
    case SeedCommand():
      await _withSession(command, (s) => _seed(s, command));
    case CleanupCommand():
      await _withSession(command, (s) => _cleanup(s, command));
    case InspectCommand():
      await _withSession(command, _inspect);
  }
}

void _listScenarios() {
  final now = DateTime.now();
  stdout.writeln('Available demo scenarios:\n');
  for (final s in DemoScenario.values) {
    final count = generateDemoWorkouts(s, referenceDate: now).length;
    stdout.writeln('  ${s.key}  (${s.title}, $count workouts)');
    stdout.writeln('      ${s.description}\n');
  }
  stdout.writeln('Seed one with:');
  stdout.writeln('  dart run tool/seed_data.dart seed --scenario <key>');
}

// ---- session (config + sign-in) ----

class _Session {
  final CliConfig config;
  final String uid;
  final String email;
  final String idToken;

  _Session(this.config, this.uid, this.email, this.idToken);
}

Future<void> _withSession(
  CliCommand command,
  Future<void> Function(_Session) run,
) async {
  final (config, missing) = readCliConfig(Platform.environment);
  if (config == null) {
    stderr.writeln(
      'Error: missing required environment variable'
      '${missing.length == 1 ? '' : 's'}: ${missing.join(', ')}\n',
    );
    stdout.writeln(cliUsage);
    exitCode = 78; // EX_CONFIG
    return;
  }

  final email = config.email ?? _promptLine('Email: ');
  final password = config.password ?? _promptLine('Password: ');

  stdout.writeln('\nSigning in to project "${config.projectId}"...');
  final Map<String, dynamic> auth;
  try {
    auth = await _jsonPost(
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

// ---- commands ----

Future<void> _seed(_Session s, SeedCommand cmd) async {
  final now = DateTime.now();
  final specs = generateDemoWorkouts(cmd.scenario, referenceDate: now);

  final existing = await _listWorkoutDocuments(s);
  final selection = selectDemoDocuments(existing, batchId: cmd.batchId);

  stdout.writeln(
    'Plan for seed (scenario=${cmd.scenario.key}, '
    'batch=${cmd.batchId}):',
  );
  stdout.writeln(
    '  replace ${selection.selectedIds.length} existing '
    'document(s) in this demo batch',
  );
  stdout.writeln('  write   ${specs.length} demo workout(s)');
  stdout.writeln(
    '  ignore  ${selection.normalDocuments} normal workout(s) '
    'and ${selection.otherDemoDocuments} demo document(s) in other '
    'batches (never touched)',
  );

  if (cmd.dryRun) {
    stdout.writeln('\nDry run: nothing was written.');
    return;
  }
  if (!_confirm(
    '\nThis WRITES to project "${s.config.projectId}" as ${s.email}.',
    assumeYes: cmd.assumeYes,
  )) {
    return;
  }

  for (final id in selection.selectedIds) {
    await _deleteDocument(s, id);
  }
  final generatedAt = now.toUtc();
  var written = 0;
  for (final spec in specs) {
    await _patchDocument(
      s,
      spec.documentId,
      _specToRestFields(spec, cmd.scenario, cmd.batchId, generatedAt),
    );
    written++;
    stdout.write('\r  written $written / ${specs.length}');
  }
  stdout.writeln(
    '\nDone: replaced ${selection.selectedIds.length}, wrote $written '
    'workout(s) into batch "${cmd.batchId}".',
  );
  stdout.writeln(
    'Note: a running app shows the new data after pull-to-refresh or '
    'restart (no realtime listeners by design).',
  );
}

Future<void> _cleanup(_Session s, CleanupCommand cmd) async {
  final existing = await _listWorkoutDocuments(s);
  final selection = selectDemoDocuments(existing, batchId: cmd.batchId);
  final scope = cmd.batchId == null
      ? 'ALL demo batches'
      : 'demo batch "${cmd.batchId}"';

  stdout.writeln('Plan for cleanup ($scope):');
  stdout.writeln(
    '  delete ${selection.selectedIds.length} tagged demo '
    'document(s)',
  );
  stdout.writeln(
    '  keep   ${selection.otherDemoDocuments} demo document(s) '
    'in other batches',
  );
  stdout.writeln(
    '  keep   ${selection.normalDocuments} normal workout(s) '
    '(never touched)',
  );

  if (cmd.dryRun) {
    stdout.writeln('\nDry run: nothing was deleted.');
    return;
  }
  if (selection.selectedIds.isEmpty) {
    stdout.writeln('\nNothing to delete.');
    return;
  }
  if (!_confirm(
    '\nThis DELETES ${selection.selectedIds.length} demo document(s) from '
    'project "${s.config.projectId}" as ${s.email}.',
    assumeYes: cmd.assumeYes,
  )) {
    return;
  }

  var deleted = 0;
  for (final id in selection.selectedIds) {
    await _deleteDocument(s, id);
    deleted++;
    stdout.write('\r  deleted $deleted / ${selection.selectedIds.length}');
  }
  stdout.writeln('\nDone: deleted $deleted demo document(s).');
}

Future<void> _inspect(_Session s) async {
  final existing = await _listWorkoutDocuments(s);
  final byBatch = <String, int>{};
  var normal = 0;
  for (final (_, data) in existing) {
    if (isDemoDocument(data)) {
      final batch = data[demoFieldBatchId] as String? ?? '(untagged batch)';
      byBatch[batch] = (byBatch[batch] ?? 0) + 1;
    } else {
      normal++;
    }
  }
  stdout.writeln('Workout documents for this user:');
  stdout.writeln('  normal (never touched by this tool): $normal');
  if (byBatch.isEmpty) {
    stdout.writeln('  demo: none');
    return;
  }
  for (final e in byBatch.entries) {
    stdout.writeln('  demo batch "${e.key}": ${e.value}');
  }
  stdout.writeln('\nRemove one with: cleanup --batch <id>   (or --all)');
}

// ---- Firestore REST helpers ----

Uri _docsBase(_Session s) => Uri.parse(
  'https://firestore.googleapis.com/v1/projects/${s.config.projectId}'
  '/databases/(default)/documents/users/${s.uid}/workouts',
);

Future<List<(String, Map<String, dynamic>)>> _listWorkoutDocuments(
  _Session s,
) async {
  final results = <(String, Map<String, dynamic>)>[];
  String? pageToken;
  do {
    final uri = _docsBase(
      s,
    ).replace(queryParameters: {'pageSize': '300', 'pageToken': ?pageToken});
    final body = await _jsonGet(uri, s.idToken);
    for (final doc in (body['documents'] as List? ?? const [])) {
      final map = doc as Map<String, dynamic>;
      final name = map['name'] as String;
      results.add((
        name.substring(name.lastIndexOf('/') + 1),
        _decodeRestFields(map['fields'] as Map<String, dynamic>? ?? const {}),
      ));
    }
    pageToken = body['nextPageToken'] as String?;
  } while (pageToken != null);
  return results;
}

/// Decodes only the flat fields cleanup selection needs (demo tags);
/// nested workout content is irrelevant to selection and left out.
Map<String, dynamic> _decodeRestFields(Map<String, dynamic> fields) {
  final out = <String, dynamic>{};
  for (final e in fields.entries) {
    final v = e.value as Map<String, dynamic>;
    if (v.containsKey('booleanValue')) out[e.key] = v['booleanValue'];
    if (v.containsKey('stringValue')) out[e.key] = v['stringValue'];
  }
  return out;
}

Map<String, dynamic> _specToRestFields(
  DemoWorkoutSpec spec,
  DemoScenario scenario,
  String batchId,
  DateTime generatedAtUtc,
) {
  Map<String, dynamic> setFields(DemoSet set) => {
    'mapValue': {
      'fields': {
        'weight': {'doubleValue': set.weight},
        'reps': {'integerValue': '${set.reps}'},
        if (set.isWarmup) 'isWarmup': {'booleanValue': true},
      },
    },
  };

  return {
    'fields': {
      'date': {'timestampValue': spec.date.toUtc().toIso8601String()},
      if (spec.name.isNotEmpty) 'name': {'stringValue': spec.name},
      if (spec.feelRating != null)
        'feelRating': {'integerValue': '${spec.feelRating}'},
      'exercises': {
        'arrayValue': {
          'values': [
            for (final ex in spec.exercises)
              {
                'mapValue': {
                  'fields': {
                    'name': {'stringValue': ex.name},
                    'sets': {
                      'arrayValue': {
                        'values': [for (final set in ex.sets) setFields(set)],
                      },
                    },
                  },
                },
              },
          ],
        },
      },
      // demo tags - keep in lockstep with demoTagFields (demo_plan.dart)
      demoFieldIsDemo: {'booleanValue': true},
      demoFieldScenario: {'stringValue': scenario.key},
      demoFieldBatchId: {'stringValue': batchId},
      demoFieldGeneratedAt: {'stringValue': generatedAtUtc.toIso8601String()},
    },
  };
}

Future<void> _patchDocument(
  _Session s,
  String docId,
  Map<String, dynamic> body,
) async {
  final uri = Uri.parse('${_docsBase(s)}/$docId');
  await _jsonRequest('PATCH', uri, s.idToken, body);
}

Future<void> _deleteDocument(_Session s, String docId) async {
  final uri = Uri.parse('${_docsBase(s)}/$docId');
  await _jsonRequest('DELETE', uri, s.idToken, null);
}

Future<Map<String, dynamic>> _jsonGet(Uri uri, String token) =>
    _jsonRequest('GET', uri, token, null);

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
      throw Exception('$method $uri -> HTTP ${res.statusCode}: $raw');
    }
    return raw.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<Map<String, dynamic>> _jsonPost(Uri uri, Map<String, dynamic> body) {
  return _jsonRequestNoAuth(uri, body);
}

Future<Map<String, dynamic>> _jsonRequestNoAuth(
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
      throw Exception('HTTP ${res.statusCode}: $raw');
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}
