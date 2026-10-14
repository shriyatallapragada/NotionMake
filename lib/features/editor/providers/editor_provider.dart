import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../data/draft_store.dart';
import '../models/builtin_templates.dart';
import '../models/template_model.dart';

final draftStoreProvider = Provider((_) => DraftStore());

class EditorState {
  final Template template;
  final bool canUndo;
  final bool canRedo;
  const EditorState(this.template, {this.canUndo = false, this.canRedo = false});
}

/// The template being edited, with undo/redo and debounced autosave.
class EditorNotifier extends Notifier<EditorState> {
  static const _maxHistory = 100;
  static const _coalesceWindow = Duration(milliseconds: 1500);

  final List<Template> _undo = [];
  final List<Template> _redo = [];
  String? _lastKey;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _saveTimer;
  bool _touched = false;

  @override
  EditorState build() {
    ref.onDispose(() => _saveTimer?.cancel());
    Future.microtask(_restoreDraft);
    return EditorState(dailyPlanner());
  }

  Future<void> _restoreDraft() async {
    final saved = await ref.read(draftStoreProvider).loadDraft();
    if (saved != null && !_touched) state = EditorState(saved);
  }

  EditorState _snapshot(Template t) =>
      EditorState(t, canUndo: _undo.isNotEmpty, canRedo: _redo.isNotEmpty);

  /// Applies a change. Edits with the same [key] within 1.5s (typing in one
  /// field) merge into a single undo step.
  void _commit(Template next, {String? key}) {
    _touched = true;
    final now = DateTime.now();
    final merge = key != null && key == _lastKey && now.difference(_lastAt) < _coalesceWindow;
    if (!merge) {
      _undo.add(state.template);
      if (_undo.length > _maxHistory) _undo.removeAt(0);
    }
    _redo.clear();
    _lastKey = key;
    _lastAt = now;
    state = _snapshot(next);
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 600),
      () => ref.read(draftStoreProvider).saveDraft(state.template),
    );
  }

  Template get _t => state.template;

  void setMeta({String? title, String? icon, String? coverUrl}) => _commit(
    _t.copyWith(title: title, icon: icon, coverUrl: coverUrl),
    key:
        'meta-${title != null
            ? 't'
            : icon != null
            ? 'i'
            : 'c'}',
  );

  void updateBlock(String id, TemplateBlock Function(TemplateBlock) f, {bool typing = false}) {
    _commit(_t.copyWith(blocks: _t.blocks.edit(id, (b) => [f(b)])), key: typing ? 'blk-$id' : null);
  }

  /// Adds a block at the end of the page, or inside a toggle ([parentId]) or
  /// one column of a columns block ([parentId] + [column]). Containers and
  /// databases are only allowed at the top level.
  void addBlock(BlockType type, {String? parentId, int? column}) {
    final block = TemplateBlock.blank(type);
    if (parentId == null) {
      _commit(_t.copyWith(blocks: [..._t.blocks, block]));
      return;
    }
    if (type.topLevelOnly) return;
    _commit(
      _t.copyWith(
        blocks: _t.blocks.edit(parentId, (p) {
          if (column != null && column < p.columns.length) {
            final cols = [
              for (final c in p.columns) [...c],
            ];
            cols[column].add(block);
            return [p.copyWith(columns: cols)];
          }
          return [
            p.copyWith(children: [...p.children, block]),
          ];
        }),
      ),
    );
  }

  void removeBlock(String id) => _commit(_t.copyWith(blocks: _t.blocks.edit(id, (_) => [])));

  void duplicateBlock(String id) =>
      _commit(_t.copyWith(blocks: _t.blocks.edit(id, (b) => [b, b.withFreshIds()])));

  /// Moves a block up (-1) or down (+1) among its siblings, at any depth.
  void nudgeBlock(String id, int delta) => _commit(_t.copyWith(blocks: _t.blocks.move(id, delta)));

  /// Adds or removes a column of a columns block (2 to 3 columns).
  void setColumnCount(String id, int count) {
    if (count < 2 || count > TemplateBlock.maxColumns) return;
    updateBlock(id, (b) {
      final cols = [...b.columns];
      while (cols.length < count) {
        cols.add([TemplateBlock.paragraph('')]);
      }
      return b.copyWith(columns: cols.sublist(0, count));
    });
  }

  /// [newIndex] is the final position (ReorderableListView.onReorderItem).
  void moveBlock(int oldIndex, int newIndex) {
    final list = [..._t.blocks];
    if (oldIndex == newIndex) return;
    list.insert(newIndex, list.removeAt(oldIndex));
    _commit(_t.copyWith(blocks: list));
  }

  void applyTheme(TemplateTheme theme) => _commit(_t.withTheme(theme));

  void loadTemplate(Template t) => _commit(t.fresh());

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(state.template);
    _lastKey = null;
    state = _snapshot(_undo.removeLast());
    _scheduleSave();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(state.template);
    _lastKey = null;
    state = _snapshot(_redo.removeLast());
    _scheduleSave();
  }
}

final editorProvider = NotifierProvider<EditorNotifier, EditorState>(EditorNotifier.new);

/// The user's saved templates.
class UserTemplatesNotifier extends Notifier<List<Template>> {
  @override
  List<Template> build() {
    Future.microtask(() async {
      final saved = await ref.read(draftStoreProvider).loadTemplates();
      if (saved.isNotEmpty && state.isEmpty) state = saved;
    });
    return [];
  }

  void save(Template t) {
    state = [...state, t.fresh()];
    ref.read(draftStoreProvider).saveTemplates(state);
  }

  void delete(int index) {
    state = [...state]..removeAt(index);
    ref.read(draftStoreProvider).saveTemplates(state);
  }
}

final userTemplatesProvider = NotifierProvider<UserTemplatesNotifier, List<Template>>(
  UserTemplatesNotifier.new,
);

/// The user's saved widget links (clock, weather, calendar...).
class SavedWidget {
  final String name;
  final String url;
  const SavedWidget(this.name, this.url);
}

class WidgetCatalogNotifier extends Notifier<List<SavedWidget>> {
  @override
  List<SavedWidget> build() {
    Future.microtask(() async {
      final saved = await ref.read(draftStoreProvider).loadWidgets();
      if (saved.isNotEmpty && state.isEmpty) {
        state = [for (final w in saved) SavedWidget(w['name']!, w['url']!)];
      }
    });
    return [];
  }

  void _persist() => ref.read(draftStoreProvider).saveWidgets([
    for (final w in state) {'name': w.name, 'url': w.url},
  ]);

  void add(String name, String url) {
    state = [...state.where((w) => w.url != url), SavedWidget(name, url)];
    _persist();
  }

  void remove(SavedWidget w) {
    state = state.where((x) => x != w).toList();
    _persist();
  }
}

final widgetCatalogProvider = NotifierProvider<WidgetCatalogNotifier, List<SavedWidget>>(
  WidgetCatalogNotifier.new,
);
