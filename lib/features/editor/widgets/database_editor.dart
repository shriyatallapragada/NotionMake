import 'package:flutter/material.dart';

import '../../../core/notion/database_mapper.dart';
import '../models/template_model.dart';
import 'synced_field.dart';

typedef BlockEdit = void Function(TemplateBlock Function(TemplateBlock), {bool typing});

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Editor for a database block: its title, columns, and sample rows.
class DatabaseEditor extends StatelessWidget {
  final TemplateBlock block;
  final BlockEdit edit;
  const DatabaseEditor({super.key, required this.block, required this.edit});

  void _setProp(String id, DbProperty Function(DbProperty) f, {bool typing = false}) => edit(
    (b) => b.copyWith(properties: [for (final p in b.properties) p.id == id ? f(p) : p]),
    typing: typing,
  );

  void _setCell(String rowId, String propId, String v, {bool typing = false}) => edit(
    (b) => b.copyWith(rows: [for (final r in b.rows) r.id == rowId ? r.withValue(propId, v) : r]),
    typing: typing,
  );

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Database · a table inside the page', style: label),
        const SizedBox(height: 8),
        SyncedField(
          value: block.text,
          decoration: const InputDecoration(labelText: 'Database title'),
          onChanged: (v) => edit((b) => b.copyWith(text: v), typing: true),
        ),
        const SizedBox(height: 12),
        Text('Columns', style: label),
        for (var i = 0; i < block.properties.length; i++) _propEditor(context, i),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add column'),
            onPressed: block.properties.length >= TemplateBlock.maxDbProperties
                ? null
                : () => edit(
                    (b) => b.copyWith(
                      properties: [
                        ...b.properties,
                        DbProperty.make('Column ${b.properties.length + 1}', DbPropType.text),
                      ],
                    ),
                  ),
          ),
        ),
        if (block.properties.any((p) => p.type == DbPropType.checkbox)) ...[
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Progress bar',
              isDense: true,
              helperText:
                  'Adds a small linked table above this one that Notion keeps up to date as boxes are '
                  'ticked, on every device.',
              helperMaxLines: 3,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                value: block.progressColumn?.id ?? '',
                items: [
                  const DropdownMenuItem(value: '', child: Text('None')),
                  for (final p in block.properties.where((p) => p.type == DbPropType.checkbox))
                    DropdownMenuItem(value: p.id, child: Text('Follow "${p.name}"')),
                ],
                onChanged: (v) => edit((b) => b.copyWith(progress: v ?? '')),
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text('Sample rows (${block.rows.length}/${TemplateBlock.maxDbRows})', style: label),
        for (final row in block.rows) _rowEditor(context, row),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add row'),
            onPressed: block.rows.length >= TemplateBlock.maxDbRows
                ? null
                : () => edit(
                    (b) => b.copyWith(
                      rows: [
                        ...b.rows,
                        DbRow(id: newBlockId()),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _propEditor(BuildContext context, int i) {
    final p = block.properties[i];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SyncedField(
                  value: p.name,
                  decoration: InputDecoration(
                    labelText: i == 0 ? 'Title column' : 'Column name',
                    isDense: true,
                  ),
                  onChanged: (v) => _setProp(p.id, (x) => x.copyWith(name: v), typing: true),
                ),
              ),
              const SizedBox(width: 8),
              if (i == 0)
                const Chip(label: Text('Title'), visualDensity: VisualDensity.compact)
              else
                DropdownButton<DbPropType>(
                  value: p.type,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final t in DbPropType.values.where((t) => t != DbPropType.title))
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (t) => t == null ? null : _setProp(p.id, (x) => x.copyWith(type: t)),
                ),
              if (i > 0)
                IconButton(
                  tooltip: 'Remove column',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => edit(
                    (b) => b.copyWith(properties: b.properties.where((x) => x.id != p.id).toList()),
                  ),
                ),
            ],
          ),
          if (p.type.hasOptions)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SyncedField(
                value: p.optionsText,
                decoration: const InputDecoration(
                  labelText: 'Options, separated by commas',
                  isDense: true,
                ),
                onChanged: (v) => _setProp(p.id, (x) => x.copyWith(optionsText: v), typing: true),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rowEditor(BuildContext context, DbRow row) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Remove row',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () =>
                  edit((b) => b.copyWith(rows: b.rows.where((r) => r.id != row.id).toList())),
            ),
          ),
          for (final p in block.properties)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 8),
              child: _cell(context, p, row),
            ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, DbProperty p, DbRow row) {
    final v = row.values[p.id] ?? '';
    switch (p.type) {
      case DbPropType.checkbox:
        return CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(p.name),
          value: v == 'true',
          onChanged: (c) => _setCell(row.id, p.id, c == true ? 'true' : 'false'),
        );
      case DbPropType.select:
        final opts = p.options;
        return InputDecorator(
          decoration: InputDecoration(labelText: p.name, isDense: true),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: true,
              value: opts.contains(v) ? v : '',
              items: [
                const DropdownMenuItem(value: '', child: Text('(none)')),
                for (final o in opts) DropdownMenuItem(value: o, child: Text(o)),
              ],
              onChanged: (x) => _setCell(row.id, p.id, x ?? ''),
            ),
          ),
        );
      case DbPropType.multiSelect:
        final chosen = {
          for (final s in v.split(','))
            if (s.trim().isNotEmpty) s.trim(),
        };
        return InputDecorator(
          decoration: InputDecoration(labelText: p.name, isDense: true),
          child: p.options.isEmpty
              ? const Text('Add options to this column first')
              : Wrap(
                  spacing: 6,
                  children: [
                    for (final o in p.options)
                      FilterChip(
                        label: Text(o),
                        selected: chosen.contains(o),
                        onSelected: (on) {
                          final next = on ? {...chosen, o} : ({...chosen}..remove(o));
                          _setCell(
                            row.id,
                            p.id,
                            [
                              for (final x in p.options)
                                if (next.contains(x)) x,
                            ].join(', '),
                          );
                        },
                      ),
                  ],
                ),
        );
      case DbPropType.date:
        return Row(
          children: [
            Expanded(child: Text(v.isEmpty ? '${p.name}: no date' : '${p.name}: $v')),
            Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: isValidDbDate(v) ? DateTime.parse(v) : DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) _setCell(row.id, p.id, _fmtDate(picked));
                },
                child: const Text('Pick'),
              ),
            ),
            if (v.isNotEmpty)
              IconButton(
                tooltip: 'Clear date',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _setCell(row.id, p.id, ''),
              ),
          ],
        );
      case DbPropType.number:
        final bad = v.trim().isNotEmpty && double.tryParse(v.trim()) == null;
        return SyncedField(
          value: v,
          decoration: InputDecoration(
            labelText: p.name,
            isDense: true,
            errorText: bad ? 'Must be a number' : null,
          ),
          onChanged: (x) => _setCell(row.id, p.id, x, typing: true),
        );
      case DbPropType.url:
        return SyncedField(
          value: v,
          decoration: InputDecoration(labelText: '${p.name} (link)', isDense: true),
          onChanged: (x) => _setCell(row.id, p.id, x, typing: true),
        );
      case DbPropType.title:
      case DbPropType.text:
        return SyncedField(
          value: v,
          decoration: InputDecoration(labelText: p.name, isDense: true),
          onChanged: (x) => _setCell(row.id, p.id, x, typing: true),
        );
    }
  }
}
