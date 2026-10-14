import 'package:flutter/material.dart';

/// A TextField whose text follows [value] when it changes from outside
/// (undo, loading a template) without disturbing the cursor while typing.
class SyncedField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final InputDecoration? decoration;
  final int? maxLines;
  final TextAlign textAlign;
  final TextStyle? style;

  const SyncedField({
    super.key,
    required this.value,
    required this.onChanged,
    this.decoration,
    this.maxLines = 1,
    this.textAlign = TextAlign.start,
    this.style,
  });

  @override
  State<SyncedField> createState() => _SyncedFieldState();
}

class _SyncedFieldState extends State<SyncedField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(SyncedField old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text) {
      _c.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    onChanged: widget.onChanged,
    decoration: widget.decoration,
    minLines: 1,
    maxLines: widget.maxLines,
    textAlign: widget.textAlign,
    style: widget.style,
  );
}
