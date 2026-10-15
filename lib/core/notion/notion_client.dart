import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants.dart';
import 'notion_exceptions.dart';

class NotionPage {
  final String id;
  final String title;
  final String? icon;
  final String? url;
  const NotionPage({required this.id, required this.title, this.icon, this.url});

  factory NotionPage.fromJson(Map<String, dynamic> json) {
    var title = 'Untitled';
    final props = json['properties'] as Map<String, dynamic>? ?? {};
    for (final p in props.values) {
      if (p is Map && p['type'] == 'title') {
        final parts = (p['title'] as List?) ?? [];
        final t = parts.map((e) => e['plain_text'] ?? '').join();
        if (t.isNotEmpty) title = t;
      }
    }
    final icon = json['icon'];
    return NotionPage(
      id: json['id'] as String,
      title: title,
      icon: icon is Map && icon['type'] == 'emoji' ? icon['emoji'] as String : null,
      url: json['url'] as String?,
    );
  }
}

class SearchResult {
  final List<NotionPage> pages;
  final String? nextCursor;
  const SearchResult(this.pages, this.nextCursor);
}

/// Thin Notion REST client: auth headers, retry on 429, error mapping.
class NotionClient {
  final String token;
  final http.Client _http;
  final Duration _retryBase;
  static const _maxRetries = 3;

  NotionClient(this.token, {http.Client? httpClient, Duration? retryBase})
    : _http = httpClient ?? http.Client(),
      _retryBase = retryBase ?? const Duration(seconds: 1);

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
    'Notion-Version': NotionConstants.apiVersion,
  };

  Future<Map<String, dynamic>> _send(String method, String path, [Object? body]) async {
    final uri = Uri.parse('${NotionConstants.baseUrl}$path');
    for (var attempt = 0; ; attempt++) {
      http.Response res;
      try {
        final req = http.Request(method, uri)..headers.addAll(_headers);
        if (body != null) req.body = jsonEncode(body);
        res = await http.Response.fromStream(
          await _http.send(req).timeout(const Duration(seconds: 30)),
        );
      } on TimeoutException {
        throw const NotionNetworkException();
      } on http.ClientException {
        throw const NotionNetworkException();
      }

      if (res.statusCode == 429 && attempt < _maxRetries) {
        final secs = double.tryParse(res.headers['retry-after'] ?? '');
        await Future<void>.delayed(
          secs != null ? Duration(milliseconds: (secs * 1000).round()) : _retryBase * (attempt + 1),
        );
        continue;
      }
      Map<String, dynamic>? json;
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}
      if (res.statusCode >= 200 && res.statusCode < 300 && json != null) {
        return json;
      }
      throw NotionException.fromResponse(res.statusCode, json);
    }
  }

  /// Validates the token; returns the integration/bot name.
  Future<String> getBotName() async {
    final me = await _send('GET', '/users/me');
    return (me['name'] as String?) ?? 'your integration';
  }

  /// Pages shared with the integration, most recently edited first.
  Future<SearchResult> searchPages({String query = '', String? cursor}) async {
    final res = await _send('POST', '/search', {
      if (query.isNotEmpty) 'query': query,
      'filter': {'property': 'object', 'value': 'page'},
      'sort': {'direction': 'descending', 'timestamp': 'last_edited_time'},
      'page_size': 50,
      'start_cursor': ?cursor,
    });
    final pages = (res['results'] as List)
        .map((e) => NotionPage.fromJson(e as Map<String, dynamic>))
        .toList();
    return SearchResult(pages, res['has_more'] == true ? res['next_cursor'] as String? : null);
  }

  Future<Map<String, dynamic>> createPage(Map<String, dynamic> payload) =>
      _send('POST', '/pages', payload);

  /// Creates a database; the response contains its `id`.
  Future<Map<String, dynamic>> createDatabase(Map<String, dynamic> payload) =>
      _send('POST', '/databases', payload);

  /// Adds or changes properties of a database (PATCH /v1/databases/{id}).
  Future<Map<String, dynamic>> updateDatabase(String id, Map<String, dynamic> payload) =>
      _send('PATCH', '/databases/$id', payload);

  Future<void> appendChildren(String blockId, List<Map<String, dynamic>> children) =>
      _send('PATCH', '/blocks/$blockId/children', {'children': children});
}
