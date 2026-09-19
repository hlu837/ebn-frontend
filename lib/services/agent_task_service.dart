import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/agent_task.dart';

/// Thrown for any agent-tasks call the backend rejects or that fails to
/// reach the server. [message] is safe to show directly in a SnackBar.
class AgentTaskException implements Exception {
  final String message;
  const AgentTaskException(this.message);

  @override
  String toString() => message;
}

/// Talks to `/api/agent-tasks` — the real to-do list behind the dashboard's
/// "Tasks" quick action.
class AgentTaskService {
  static const String baseUrl = ApiConfig.baseUrl;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  String _requireToken(String token) {
    final cleaned = token.trim();
    if (cleaned.isEmpty) {
      throw const AgentTaskException(
          'Your session has expired. Please sign in again.');
    }
    return cleaned;
  }

  Future<List<AgentTask>> list({required String token}) async {
    final authToken = _requireToken(token);
    final res = await _get('/api/agent-tasks', token: authToken);
    return (jsonDecode(res) as List)
        .map((e) => AgentTask.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// A random UUID (v4). Generated once per "Add task" tap and sent with the
  /// create call: if the request has to be retried (slow server, lost
  /// response) the backend recognises the id and returns the task it already
  /// saved instead of creating a duplicate. It also lets the screen check
  /// whether a task that "failed" actually made it to the server.
  static String newId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }

  Future<AgentTask> create({
    required String token,
    required String title,
    DateTime? dueAt,
    String? id,
  }) async {
    final authToken = _requireToken(token);
    final res = await _send(
      'POST',
      '/api/agent-tasks',
      body: {
        'id': id ?? newId(),
        'title': title,
        if (dueAt != null) 'dueAt': dueAt.toIso8601String(),
      },
      token: authToken,
    );
    return AgentTask.fromJson(jsonDecode(res) as Map<String, dynamic>);
  }

  Future<AgentTask> setDone(
      {required String token, required String id, required bool done}) async {
    final authToken = _requireToken(token);
    final res = await _send('PATCH', '/api/agent-tasks/$id',
        body: {'done': done}, token: authToken);
    return AgentTask.fromJson(jsonDecode(res) as Map<String, dynamic>);
  }

  Future<void> delete({required String token, required String id}) async {
    final authToken = _requireToken(token);
    // 404 = already gone (e.g. an earlier attempt did go through), which is
    // exactly the outcome we wanted — not an error.
    await _send('DELETE', '/api/agent-tasks/$id', token: authToken, okOn404: true);
  }

  // ── internals ────────────────────────────────────────────────────────

  Future<String> _get(String path, {required String token}) {
    return _run(
      () => http.get(_uri(path), headers: {'Authorization': 'Bearer $token'}),
      timeout: const Duration(seconds: 20),
    );
  }

  Future<String> _send(String method, String path,
      {Map<String, dynamic>? body, required String token, bool okOn404 = false}) {
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token'
    };
    return _run(
      () {
        switch (method) {
          case 'POST':
            return http.post(_uri(path), headers: headers, body: jsonEncode(body ?? {}));
          case 'PATCH':
            return http.patch(_uri(path), headers: headers, body: jsonEncode(body ?? {}));
          case 'DELETE':
            return http.delete(_uri(path), headers: headers);
          default:
            throw ArgumentError('Unsupported method: $method');
        }
      },
      // Writes get longer: the backend runs serverless, so the first call
      // after a quiet spell can spend several seconds just starting up.
      timeout: const Duration(seconds: 25),
      okOn404: okOn404,
    );
  }

  /// Runs [call] and retries it once if it timed out, couldn't connect, or
  /// the server answered 5xx (cold start / dropped database connection).
  /// Every call this service makes is safe to repeat: reads and PATCH are
  /// idempotent, DELETE treats "already gone" as success, and create carries
  /// a client-generated id the backend de-duplicates on. Real rejections
  /// (400/401/403/404...) are never retried.
  Future<String> _run(
    Future<http.Response> Function() call, {
    required Duration timeout,
    bool okOn404 = false,
  }) async {
    const attempts = 2;
    for (var i = 0; i < attempts; i++) {
      final isLast = i == attempts - 1;
      try {
        final res = await call().timeout(timeout);
        if (res.statusCode >= 500 && !isLast) {
          throw const _Transient();
        }
        if (okOn404 && res.statusCode == 404) return res.body;
        return _decode(res);
      } on AgentTaskException {
        rethrow;
      } catch (_) {
        if (isLast) {
          throw const AgentTaskException(
              "Couldn't reach the server. Check your connection and try again.");
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    throw const AgentTaskException(
        "Couldn't reach the server. Check your connection and try again.");
  }

  String _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String message = 'Something went wrong (${res.statusCode}).';
      try {
        final json = jsonDecode(res.body);
        if (json is Map<String, dynamic> && json['error'] is String) {
          message = json['error'] as String;
        }
      } catch (_) {}
      throw AgentTaskException(message);
    }
    return res.body;
  }
}

/// Internal marker: "this attempt failed in a way worth retrying".
class _Transient implements Exception {
  const _Transient();
}
