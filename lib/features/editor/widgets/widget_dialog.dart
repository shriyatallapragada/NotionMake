import 'package:flutter/material.dart';

import '../../../core/notion/database_mapper.dart' show isValidDbDate;
import '../../../core/widget_library.dart';

/// Lets the user set up one of the built-in widgets. Returns its link, or null
/// if cancelled.
Future<String?> showWidgetDialog(
  BuildContext context,
  LibraryWidget widget, {
  Map<String, String> initial = const {},
}) => showDialog<String>(
  context: context,
  builder: (_) => _WidgetDialog(widget: widget, initial: initial),
);

class _WidgetDialog extends StatefulWidget {
  final LibraryWidget widget;
  final Map<String, String> initial;
  const _WidgetDialog({required this.widget, required this.initial});
  @override
  State<_WidgetDialog> createState() => _WidgetDialogState();
}

class _WidgetDialogState extends State<_WidgetDialog> {
  late final Map<String, String> _values = {...widget.initial};
  final _controllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(String name) => _controllers.putIfAbsent(name, () {
    final v = _values[name] ?? '';
    // Saved links separate tasks with "|"; the editor shows one per line.
    final text = widget.widget.option(name)?.kind == OptionKind.itemList
        ? v.replaceAll('|', '\n')
        : v;
    return TextEditingController(text: text);
  });

  void _set(String name, String v) =>
      setState(() => v.isEmpty ? _values.remove(name) : _values[name] = v);

  @override
  Widget build(BuildContext context) {
    final w = widget.widget;
    final built = WidgetLibrary.build(w.kind, _values);
    final errors = built?.errors ?? const {};
    return AlertDialog(
      title: Text('${w.icon}  ${w.label}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(w.description),
              const SizedBox(height: 12),
              for (final o in w.options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _field(o, errors[o.name]),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: built?.url == null ? null : () => Navigator.pop(context, built!.url),
          child: const Text('Use this widget'),
        ),
      ],
    );
  }

  Widget _field(WidgetOption o, String? error) {
    final shown = (_values[o.name] ?? '').isEmpty ? null : error;
    final label = o.required ? '${o.label} *' : o.label;
    switch (o.kind) {
      case OptionKind.choice:
      case OptionKind.flag:
        final items = o.kind == OptionKind.flag
            ? const {'': 'Default', '1': 'On', '0': 'Off'}
            : {'': 'Default (${o.defaultValue})', for (final c in o.choices) c: c};
        return InputDecorator(
          decoration: InputDecoration(labelText: label, isDense: true),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: true,
              value: _values[o.name] ?? '',
              items: [
                for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => _set(o.name, v ?? ''),
            ),
          ),
        );
      case OptionKind.date:
        return TextField(
          controller: _controller(o.name),
          decoration: InputDecoration(
            labelText: label,
            hintText: 'YYYY-MM-DD',
            isDense: true,
            errorText:
                shown ?? (o.required && (_values[o.name] ?? '').isEmpty ? 'Pick a date' : null),
            suffixIcon: IconButton(
              tooltip: 'Pick a date',
              icon: const Icon(Icons.calendar_month),
              onPressed: () async {
                final cur = _values[o.name] ?? '';
                final picked = await showDatePicker(
                  context: context,
                  initialDate: isValidDbDate(cur) ? DateTime.parse(cur) : DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked == null) return;
                final text =
                    '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                _controller(o.name).text = text;
                _set(o.name, text);
              },
            ),
          ),
          onChanged: (v) => _set(o.name, v.trim()),
        );
      case OptionKind.itemList:
        return TextField(
          controller: _controller(o.name),
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'One task per line (up to 30)',
            alignLabelWithHint: true,
            isDense: true,
            errorText:
                shown ??
                (o.required && (_values[o.name] ?? '').isEmpty ? 'Add at least one task' : null),
          ),
          onChanged: (v) => _set(o.name, v.trim()),
        );
      default:
        final hint = switch (o.kind) {
          OptionKind.indexList => 'Numbers separated by commas, for example 1, 3',
          OptionKind.integer => '${o.min}-${o.max} (default ${o.defaultValue})',
          OptionKind.time => 'HH:MM, for example 09:30',
          OptionKind.dateList => 'Dates separated by commas: 2026-11-02, 2026-11-09',
          OptionKind.month => 'YYYY-MM',
          OptionKind.timezone => 'A city or zone, for example Asia/Kolkata or London',
          _ => '',
        };
        return TextField(
          controller: _controller(o.name),
          maxLength: o.kind == OptionKind.text ? 40 : null,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
            errorText: shown,
            counterText: '',
          ),
          onChanged: (v) => _set(o.name, v.trim()),
        );
    }
  }
}
