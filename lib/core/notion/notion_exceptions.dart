/// Any failure talking to Notion, with a message safe to show to users.
class NotionException implements Exception {
  final String message;
  final String? code;
  final int? status;
  const NotionException(this.message, {this.code, this.status});

  factory NotionException.fromResponse(int status, Map<String, dynamic>? body) {
    final code = body?['code'] as String?;
    final raw = body?['message'] as String?;
    final friendly = switch (code) {
      'unauthorized' => 'Notion rejected the token. Copy it again from your integration page.',
      'restricted_resource' => "This integration isn't allowed to do that. Check its capabilities.",
      'object_not_found' =>
        "Notion can't see that page. Open it in Notion, click ... > "
            'Connections, and add your integration.',
      'rate_limited' => 'Notion is busy. Please try again in a moment.',
      'conflict_error' ||
      'internal_server_error' ||
      'service_unavailable' ||
      'gateway_timeout' => 'Notion is having trouble right now. Wait a minute and try again.',
      'invalid_grant' || 'invalid_json' || 'invalid_request' || 'invalid_request_url' =>
        'Notion could not understand that request. Please report this as a bug.',
      'validation_error' => 'Notion rejected the page content: ${raw ?? ''}',
      _ => raw ?? 'Notion returned an error ($status).',
    };
    return NotionException(friendly, code: code, status: status);
  }

  /// True when the token was rejected, so the user should reconnect.
  bool get isAuthProblem => code == 'unauthorized' || status == 401;

  @override
  String toString() => message;
}

class NotionNetworkException extends NotionException {
  const NotionNetworkException() : super('Could not reach Notion. Check your internet connection.');
}
