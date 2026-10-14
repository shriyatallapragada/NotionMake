import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../features/editor/models/template_model.dart';

/// Local persistence for the autosaved draft and the user's saved templates.
/// Every method swallows storage errors: losing a draft must never crash the app.
class DraftStore {
  static const _draftKey = 'draft_v1';
  static const _templatesKey = 'templates_v1';
  static const _widgetsKey = 'widgets_v1';

  Future<Template?> loadDraft() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_draftKey);
      if (raw == null) return null;
      return Template.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDraft(Template t) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_draftKey, jsonEncode(t.toJson()));
    } catch (_) {}
  }

  Future<List<Template>> loadTemplates() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_templatesKey);
      if (raw == null) return [];
      return [
        for (final j in jsonDecode(raw) as List) Template.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTemplates(List<Template> list) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _templatesKey,
        jsonEncode([for (final t in list) t.toJson()]),
      );
    } catch (_) {}
  }

  /// Saved widget links as {name, url} pairs.
  Future<List<Map<String, String>>> loadWidgets() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_widgetsKey);
      if (raw == null) return [];
      return [
        for (final j in jsonDecode(raw) as List)
          {'name': '${(j as Map)['name']}', 'url': '${j['url']}'},
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveWidgets(List<Map<String, String>> list) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_widgetsKey, jsonEncode(list));
    } catch (_) {}
  }
}
