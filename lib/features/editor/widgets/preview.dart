import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_theme.dart';
import '../../../core/widget_library.dart';
import '../models/template_model.dart';
import '../providers/editor_provider.dart';
import 'notion_colors.dart';

const _ink = Color(0xFF37352F);

/// Approximate, always-light rendering of the page as Notion will show it.
class PreviewPane extends ConsumerWidget {
  const PreviewPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(editorProvider.select((s) => s.template));
    // The preview imitates a (white) Notion page, so it always uses the light
    // theme: icons, dividers and text must not turn light-on-white in dark mode.
    return Theme(
      data: buildAppTheme(Brightness.light),
      child: Semantics(
        label: 'Approximate preview of the Notion page',
        child: ColoredBox(
          color: Colors.white,
          child: DefaultTextStyle(
            style: const TextStyle(color: _ink, fontSize: 16, height: 1.5),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              children: [
                if (t.coverUrl.trim().startsWith('http'))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 120,
                        child: Image.network(
                          t.coverUrl.trim(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: Color(0xFFF1F1EF),
                            child: Center(child: Text('Cover not available')),
                          ),
                        ),
                      ),
                    ),
                  ),
                Text(t.icon, style: const TextStyle(fontSize: 56)),
                const SizedBox(height: 8),
                Text(
                  t.title.isEmpty ? 'Untitled' : t.title,
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                ..._blocks(t.blocks),
                const SizedBox(height: 16),
                const Text(
                  'Approximate preview',
                  style: TextStyle(color: Color(0xFF9B9A97), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _blocks(List<TemplateBlock> list) => [for (final b in list) _block(b)];

  Widget _block(TemplateBlock b) {
    switch (b.type) {
      case BlockType.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(
            b.text,
            style: TextStyle(
              fontSize: const [30.0, 24.0, 20.0][b.level.clamp(1, 3) - 1],
              fontWeight: FontWeight.w600,
              color: notionTextColors[b.color] ?? _ink,
            ),
          ),
        );
      case BlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(b.text.isEmpty ? ' ' : b.text),
        );
      case BlockType.callout:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: notionBgColors[b.color] ?? notionBgColors['default'],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(child: Text(b.text)),
            ],
          ),
        );
      case BlockType.quote:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.only(left: 14),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: _ink, width: 3)),
          ),
          child: Text(b.text, style: const TextStyle(fontSize: 17)),
        );
      case BlockType.todo:
        return Column(
          children: [
            for (final l in b.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.check_box_outline_blank, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l)),
                  ],
                ),
              ),
          ],
        );
      case BlockType.bullet:
        return Column(
          children: [
            for (final l in b.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 6),
                    const Text('•  '),
                    Expanded(child: Text(l)),
                  ],
                ),
              ),
          ],
        );
      case BlockType.divider:
        return const Divider(height: 24);
      case BlockType.toggle:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.arrow_right, size: 22),
                  Expanded(
                    child: Text(b.text, style: const TextStyle(fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _blocks(b.children),
                ),
              ),
            ],
          ),
        );
      case BlockType.columns:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < b.columns.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _blocks(b.columns[i]),
                  ),
                ),
              ],
            ],
          ),
        );
      case BlockType.database:
        return _database(b);
      case BlockType.embed:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE3E2E0)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              const Icon(Icons.widgets_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  b.text.isEmpty
                      ? 'Embed (add a URL)'
                      : (WidgetLibrary.describe(b.text) ?? 'Embed: ${b.text}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _database(TemplateBlock b) {
    const line = Color(0xFFE3E2E0);
    Widget cell(Widget child, {bool header = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 13,
          color: header ? const Color(0xFF787774) : _ink,
          fontWeight: header ? FontWeight.w500 : FontWeight.w400,
        ),
        child: child,
      ),
    );
    Widget value(DbProperty p, DbRow r) {
      final v = r.values[p.id] ?? '';
      if (p.type == DbPropType.checkbox) {
        return Icon(v == 'true' ? Icons.check_box : Icons.check_box_outline_blank, size: 18);
      }
      return Text(v);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.table_chart_outlined, size: 18),
              const SizedBox(width: 6),
              Text(
                b.text.isEmpty ? 'Untitled database' : b.text,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (b.progressCounts case final c?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: c.total == 0 ? 0 : c.done / c.total,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFE3E2E0),
                        color: const Color(0xFF2EAADC),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    c.total == 0
                        ? 'No tasks yet'
                        : '${(c.done / c.total * 100).round()}% · ${c.done} of ${c.total}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF787774)),
                  ),
                ],
              ),
            ),
          if (b.properties.isNotEmpty)
            Table(
              border: const TableBorder(
                horizontalInside: BorderSide(color: line),
                top: BorderSide(color: line),
                bottom: BorderSide(color: line),
              ),
              children: [
                TableRow(
                  children: [for (final p in b.properties) cell(Text(p.name), header: true)],
                ),
                for (final r in b.rows)
                  TableRow(children: [for (final p in b.properties) cell(value(p, r))]),
              ],
            ),
        ],
      ),
    );
  }
}
