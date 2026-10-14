import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

enum OllamaProblem { notRunning, modelMissing, tooOld, outOfMemory, cancelled, other }

/// A failure talking to Ollama, with a message that says how to fix it.
class OllamaException implements Exception {
  final String message;
  final OllamaProblem problem;
  const OllamaException(this.message, this.problem);

  @override
  String toString() => message;

  static OllamaException notRunning() => const OllamaException(
    "Can't reach Ollama. Open the Ollama app, or run `ollama serve` in a terminal, then try again.",
    OllamaProblem.notRunning,
  );

  /// Maps Ollama's own error text (and HTTP status) to a friendly message.
  factory OllamaException.fromError(String raw, {int? status, String? model}) {
    final text = raw.toLowerCase();
    if (status == 412 || text.contains('newer version')) {
      return const OllamaException(
        'This model needs a newer version of Ollama. Update it from ollama.com/download '
        '(or run `brew upgrade ollama`), restart it, and try again.',
        OllamaProblem.tooOld,
      );
    }
    if (text.contains('memory')) {
      return const OllamaException(
        "This computer doesn't have enough free memory for that model. Close other apps or pick the "
        'lighter 4B model.',
        OllamaProblem.outOfMemory,
      );
    }
    if (status == 404 || text.contains('not found')) {
      return OllamaException(
        'The model ${model ?? ''} isn\'t downloaded yet. Download it first.'.replaceAll('  ', ' '),
        OllamaProblem.modelMissing,
      );
    }
    return OllamaException(
      raw.isEmpty ? 'Ollama returned an error ($status).' : raw,
      OllamaProblem.other,
    );
  }
}

class OllamaModel {
  final String name;
  final int sizeBytes;
  const OllamaModel(this.name, this.sizeBytes);
}

class PullProgress {
  final String status;
  final int completed;
  final int total;
  const PullProgress(this.status, this.completed, this.total);

  /// 0..1, or null when the size isn't known yet.
  double? get fraction => total > 0 ? (completed / total).clamp(0.0, 1.0) : null;
}

class OllamaReply {
  final String text;
  final int promptTokens;
  final int outputTokens;
  final String doneReason;
  const OllamaReply(this.text, this.promptTokens, this.outputTokens, this.doneReason);
}

/// Lets the UI stop a running generation or download.
class CancelToken {
  http.Client? _client;
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    _client?.close();
  }
}

/// Minimal client for Ollama's local REST API (https://github.com/ollama/ollama).
class OllamaClient {
  static const defaultHost = 'http://localhost:11434';

  final Uri base;
  final http.Client Function() _newClient;
  final Duration idleTimeout;

  OllamaClient(
    String host, {
    http.Client Function()? clientFactory,
    this.idleTimeout = const Duration(minutes: 5),
  }) : base = parseHost(host),
       _newClient = clientFactory ?? http.Client.new;

  /// Accepts "localhost:11434", "http://host:port" etc. Throws [FormatException].
  static Uri parseHost(String host) {
    var h = host.trim();
    if (h.isEmpty) h = defaultHost;
    if (!h.contains('://')) h = 'http://$h';
    final u = Uri.parse(h);
    if ((u.scheme != 'http' && u.scheme != 'https') || u.host.isEmpty) {
      throw const FormatException('Enter an address like http://localhost:11434');
    }
    return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : 11434);
  }

  /// True when Ollama runs on this computer, so nothing leaves the device.
  bool get isLocal => const {'localhost', '127.0.0.1', '::1'}.contains(base.host);

  /// Set once Ollama reports it can't enforce a JSON schema (a build without
  /// its grammar library). Later requests skip straight to plain-JSON mode.
  bool structuredOutputUnavailable = false;

  Uri _u(String path) => base.replace(path: path);

  /// Only genuine connection failures mean "Ollama isn't running"; anything
  /// else is a different problem and must not be reported that way.
  Never _connectionFailed(Object e) {
    if (e is OllamaException) throw e;
    if (e is SocketException || e is http.ClientException || e is TimeoutException) {
      throw OllamaException.notRunning();
    }
    throw OllamaException(
      'Unexpected error talking to Ollama: ${e.runtimeType}: $e',
      OllamaProblem.other,
    );
  }

  Future<Map<String, dynamic>> _json(String method, String path, [Object? body]) async {
    final client = _newClient();
    try {
      final req = http.Request(method, _u(path))..headers['Content-Type'] = 'application/json';
      if (body != null) req.body = jsonEncode(body);
      final res = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(seconds: 15)),
      );
      final data = _decode(res.body);
      if (res.statusCode >= 400) {
        throw OllamaException.fromError(
          '${data['error'] ?? ''}',
          status: res.statusCode,
          model: _modelOf(body),
        );
      }
      return data;
    } on OllamaException {
      rethrow;
    } on SocketException catch (e) {
      _connectionFailed(e);
    } on http.ClientException catch (e) {
      _connectionFailed(e);
    } on TimeoutException catch (e) {
      _connectionFailed(e);
    } finally {
      client.close();
    }
  }

  static String? _modelOf(Object? body) => body is Map ? body['model'] as String? : null;

  static Map<String, dynamic> _decode(String s) {
    try {
      final d = jsonDecode(s);
      return d is Map<String, dynamic> ? d : {};
    } catch (_) {
      return {};
    }
  }

  Future<String> version() async => '${(await _json('GET', '/api/version'))['version']}';

  Future<List<OllamaModel>> listModels() async {
    final d = await _json('GET', '/api/tags');
    return [
      for (final m in (d['models'] as List? ?? []))
        if (m is Map) OllamaModel('${m['name']}', (m['size'] as num?)?.toInt() ?? 0),
    ];
  }

  /// What the model can do: "vision", "thinking", "tools"... Empty if unknown.
  Future<Set<String>> capabilities(String model) async {
    try {
      final d = await _json('POST', '/api/show', {'model': model});
      return {for (final c in (d['capabilities'] as List? ?? [])) '$c'};
    } on OllamaException {
      return {};
    }
  }

  Stream<Map<String, dynamic>> _ndjson(String path, Object body, CancelToken? cancel) async* {
    final client = _newClient();
    cancel?._client = client;
    try {
      final req = http.Request('POST', _u(path))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
      final res = await client.send(req).timeout(const Duration(seconds: 15));
      if (res.statusCode >= 400) {
        final data = _decode(await res.stream.bytesToString());
        throw OllamaException.fromError(
          '${data['error'] ?? ''}',
          status: res.statusCode,
          model: _modelOf(body),
        );
      }
      final lines = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(
            idleTimeout,
            onTimeout: (sink) => sink.addError(TimeoutException('Ollama stopped responding')),
          );
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final d = _decode(line);
        if (d['error'] != null) {
          throw OllamaException.fromError('${d['error']}', model: _modelOf(body));
        }
        yield d;
      }
    } on OllamaException {
      rethrow;
    } on TimeoutException {
      throw const OllamaException(
        'Ollama stopped responding. The model may be too big for this computer; try the lighter 4B model.',
        OllamaProblem.other,
      );
    } catch (e) {
      if (cancel?.cancelled ?? false) {
        throw const OllamaException('Cancelled.', OllamaProblem.cancelled);
      }
      _connectionFailed(e);
    } finally {
      client.close();
    }
  }

  /// Downloads [model], reporting progress. Throws [OllamaException].
  Stream<PullProgress> pull(String model, {CancelToken? cancel}) async* {
    await for (final d in _ndjson('/api/pull', {'model': model, 'stream': true}, cancel)) {
      yield PullProgress(
        '${d['status'] ?? ''}',
        (d['completed'] as num?)?.toInt() ?? 0,
        (d['total'] as num?)?.toInt() ?? 0,
      );
    }
  }

  /// Runs one chat request with the answer constrained to [schema].
  /// [onProgress] receives the number of characters generated so far.
  Future<OllamaReply> chat({
    required String model,
    required String system,
    required String user,
    List<String> imagesBase64 = const [],
    required Map<String, dynamic> schema,
    required int numCtx,
    bool thinkOff = false,
    void Function(int chars)? onProgress,
    CancelToken? cancel,
  }) async {
    final useSchema = !structuredOutputUnavailable;
    final body = {
      'model': model,
      'stream': true,
      if (useSchema) 'format': schema,
      if (thinkOff) 'think': false,
      'keep_alive': '10m',
      'options': {'temperature': 0.3, 'num_ctx': numCtx, 'num_predict': 8192},
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user, if (imagesBase64.isNotEmpty) 'images': imagesBase64},
      ],
    };
    final out = StringBuffer();
    var promptTokens = 0, outputTokens = 0;
    var reason = '';
    try {
      await _collectChat(body, cancel, out, onProgress, (p, o, r) {
        promptTokens = p;
        outputTokens = o;
        reason = r;
      });
    } on OllamaException catch (e) {
      if (useSchema && e.message.toLowerCase().contains('structured output')) {
        structuredOutputUnavailable = true;
        return chat(
          model: model,
          system: system,
          user: user,
          imagesBase64: imagesBase64,
          schema: schema,
          numCtx: numCtx,
          thinkOff: thinkOff,
          onProgress: onProgress,
          cancel: cancel,
        );
      }
      rethrow;
    }
    return OllamaReply(out.toString(), promptTokens, outputTokens, reason);
  }

  Future<void> _collectChat(
    Map<String, Object?> body,
    CancelToken? cancel,
    StringBuffer out,
    void Function(int chars)? onProgress,
    void Function(int prompt, int output, String reason) onDone,
  ) async {
    await for (final d in _ndjson('/api/chat', body, cancel)) {
      final piece = (d['message'] is Map ? (d['message'] as Map)['content'] : null) as String?;
      if (piece != null && piece.isNotEmpty) {
        out.write(piece);
        onProgress?.call(out.length);
      }
      if (d['done'] == true) {
        onDone(
          (d['prompt_eval_count'] as num?)?.toInt() ?? 0,
          (d['eval_count'] as num?)?.toInt() ?? 0,
          '${d['done_reason'] ?? ''}',
        );
      }
    }
  }
}
