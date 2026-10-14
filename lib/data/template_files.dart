import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../features/editor/models/template_model.dart';

/// Export and import of `.notiontpl.json` files.
class TemplateFiles {
  static const maxBytes = 2 * 1024 * 1024;

  /// Asks where to save; returns true if a file was written.
  static Future<bool> export(Template t) async {
    final safe = t.title.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(t.toFileJson())),
    );
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Export template',
      fileName: '${safe.isEmpty ? 'template' : safe}.notiontpl.json',
      bytes: bytes,
      mimeType: 'application/json',
    );
    return uri != null;
  }

  /// Returns null if the user cancelled. Throws [FormatException] with a
  /// friendly message for bad files.
  static Future<Template?> import() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Import template',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return null;
    final size = await file.length();
    if (size != null && size > maxBytes) {
      throw const FormatException('That file is too large to be a template.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) {
      throw const FormatException('That file is too large to be a template.');
    }
    return parse(utf8.decode(bytes, allowMalformed: true));
  }

  static Template parse(String source) {
    try {
      final data = jsonDecode(source);
      if (data is! Map<String, dynamic>) throw const FormatException('Not a template file.');
      return Template.fromJson(data);
    } on FormatException catch (e) {
      throw FormatException(e.message.isEmpty ? 'This is not a valid template file.' : e.message);
    } catch (_) {
      throw const FormatException('This is not a valid template file.');
    }
  }
}
