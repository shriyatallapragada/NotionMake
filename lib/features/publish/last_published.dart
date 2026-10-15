import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Notion page the app published to most recently, so it can be updated
/// again with one tap.
class LastPublished {
  final String id;
  final String title;
  final String? url;
  final String? icon;
  const LastPublished({required this.id, required this.title, this.url, this.icon});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'url': url, 'icon': icon};

  static LastPublished? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return LastPublished(
      id: j['id'] as String,
      title: '${j['title'] ?? 'Untitled'}',
      url: j['url'] as String?,
      icon: j['icon'] as String?,
    );
  }
}

class LastPublishedNotifier extends Notifier<LastPublished?> {
  static const _key = 'last_published_v1';

  @override
  LastPublished? build() {
    Future.microtask(() async {
      try {
        final raw = (await SharedPreferences.getInstance()).getString(_key);
        if (raw != null && state == null) state = LastPublished.fromJson(jsonDecode(raw));
      } catch (_) {}
    });
    return null;
  }

  Future<void> set(LastPublished page) async {
    state = page;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(page.toJson()));
    } catch (_) {}
  }
}

final lastPublishedProvider = NotifierProvider<LastPublishedNotifier, LastPublished?>(
  LastPublishedNotifier.new,
);
