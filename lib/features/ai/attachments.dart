import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

class AttachmentException implements Exception {
  final String message;
  const AttachmentException(this.message);
  @override
  String toString() => message;
}

enum AttachmentKind { text, image }

/// A document the user attached: either extracted text or an image.
class AiAttachment {
  final String name;
  final AttachmentKind kind;
  final String text;
  final Uint8List? imageBytes;
  const AiAttachment.text(this.name, this.text) : kind = AttachmentKind.text, imageBytes = null;
  const AiAttachment.image(this.name, Uint8List bytes)
    : kind = AttachmentKind.image,
      text = '',
      imageBytes = bytes;
}

/// Reads documents into something a local model can use. PDFs, Word and Excel
/// files are converted to text; images are passed through for vision models.
class AttachmentReader {
  static const maxFiles = 5;
  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxTotalChars = 90000;
  static const _maxUnzippedBytes = 40 * 1024 * 1024;
  static const _maxPdfPages = 40;
  static const _maxSheetRows = 500;

  static const textExtensions = {'txt', 'md', 'csv', 'tsv', 'ics', 'json', 'html', 'htm'};
  static const imageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif'};
  static const allExtensions = {...textExtensions, ...imageExtensions, 'pdf', 'docx', 'xlsx'};

  /// Shows the file picker. Returns an empty list if cancelled.
  static Future<List<AiAttachment>> pick({int alreadyAttached = 0}) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Attach documents',
      type: FileType.custom,
      allowedExtensions: allExtensions.toList(),
    );
    if (files.length + alreadyAttached > maxFiles) {
      throw const AttachmentException('You can attach up to $maxFiles files at a time.');
    }
    final out = <AiAttachment>[];
    for (final f in files) {
      final size = await f.length();
      if (size != null && size > maxFileBytes) {
        throw AttachmentException(
          '"${f.name}" is larger than ${maxFileBytes ~/ (1024 * 1024)} MB.',
        );
      }
      out.add(await read(f.name, await f.readAsBytes()));
    }
    return out;
  }

  /// Reads one file. Throws [AttachmentException] with a message for the user.
  static Future<AiAttachment> read(String name, Uint8List bytes) async {
    if (bytes.length > maxFileBytes) {
      throw AttachmentException('"$name" is larger than ${maxFileBytes ~/ (1024 * 1024)} MB.');
    }
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    try {
      if (imageExtensions.contains(ext)) return AiAttachment.image(name, bytes);
      final text = switch (ext) {
        'pdf' => await _pdf(bytes),
        'docx' => _docx(bytes),
        'xlsx' => _xlsx(bytes),
        _ when textExtensions.contains(ext) => utf8.decode(bytes, allowMalformed: true),
        _ => throw AttachmentException('"$name" is not a supported file type.'),
      };
      if (text.trim().length < 3) {
        throw AttachmentException(
          ext == 'pdf'
              ? '"$name" has no selectable text (it may be a scan). Take a screenshot of it and attach the image instead.'
              : '"$name" looks empty.',
        );
      }
      return AiAttachment.text(name, text.trim());
    } on AttachmentException {
      rethrow;
    } catch (_) {
      throw AttachmentException('Could not read "$name". It may be damaged or password-protected.');
    }
  }

  /// Total characters of extracted text across [items].
  static int totalChars(Iterable<AiAttachment> items) => items.fold(0, (n, a) => n + a.text.length);

  // ---- PDF ----------------------------------------------------------------

  static Future<String> _pdf(Uint8List bytes) async {
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openData(bytes);
    try {
      final out = StringBuffer();
      final pages = doc.pages;
      for (var i = 0; i < pages.length && i < _maxPdfPages; i++) {
        final t = await pages[i].loadText();
        if (t != null && t.fullText.trim().isNotEmpty) {
          out.writeln('--- page ${i + 1} ---');
          out.writeln(t.fullText.trim());
        }
      }
      if (pages.length > _maxPdfPages) {
        throw AttachmentException(
          'This PDF has ${pages.length} pages; the limit is $_maxPdfPages. Attach the pages you need as a smaller file.',
        );
      }
      return out.toString();
    } finally {
      await doc.dispose();
    }
  }

  // ---- Office files (zip + XML) --------------------------------------------

  static Archive _unzip(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    var total = 0;
    for (final f in archive.files) {
      total += f.size;
      if (total > _maxUnzippedBytes) {
        throw const AttachmentException(
          'This file expands to an unreasonable size and was not opened.',
        );
      }
    }
    return archive;
  }

  static XmlDocument? _xml(Archive a, String path) {
    final f = a.findFile(path);
    if (f == null) return null;
    return XmlDocument.parse(utf8.decode(f.content, allowMalformed: true));
  }

  static String _docx(Uint8List bytes) {
    final doc = _xml(_unzip(bytes), 'word/document.xml');
    if (doc == null) throw const AttachmentException('That does not look like a Word document.');
    final out = StringBuffer();

    String paragraph(XmlElement p) {
      final s = StringBuffer();
      for (final e in p.descendantElements) {
        switch (e.name.local) {
          case 't':
            s.write(e.innerText);
          case 'tab':
            s.write('\t');
          case 'br':
            s.write(' ');
        }
      }
      return s.toString().trim();
    }

    void walk(XmlElement e) {
      for (final c in e.childElements) {
        switch (c.name.local) {
          case 'p':
            final t = paragraph(c);
            if (t.isNotEmpty) out.writeln(t);
          case 'tbl':
            for (final tr in c.childElements.where((x) => x.name.local == 'tr')) {
              final cells = [
                for (final tc in tr.childElements.where((x) => x.name.local == 'tc'))
                  tc.descendantElements
                      .where((x) => x.name.local == 'p')
                      .map(paragraph)
                      .where((t) => t.isNotEmpty)
                      .join(' '),
              ];
              if (cells.any((c) => c.isNotEmpty)) out.writeln(cells.join(' | '));
            }
          default:
            walk(c);
        }
      }
    }

    walk(doc.rootElement);
    return out.toString();
  }

  static String _xlsx(Uint8List bytes) {
    final zip = _unzip(bytes);
    final shared = <String>[
      for (final si in _xml(zip, 'xl/sharedStrings.xml')?.findAllElements('si') ?? <XmlElement>[])
        si.findAllElements('t').map((t) => t.innerText).join(),
    ];

    // Which style indexes are dates/times, so numbers like 0.375 become 09:00.
    final custom = <int, String>{
      for (final n in _xml(zip, 'xl/styles.xml')?.findAllElements('numFmt') ?? <XmlElement>[])
        int.tryParse(n.getAttribute('numFmtId') ?? '') ?? -1: n.getAttribute('formatCode') ?? '',
    };
    final xfs =
        _xml(
          zip,
          'xl/styles.xml',
        )?.findAllElements('cellXfs').expand((x) => x.findElements('xf')).toList() ??
        [];
    bool isDateStyle(int s) {
      if (s < 0 || s >= xfs.length) return false;
      final id = int.tryParse(xfs[s].getAttribute('numFmtId') ?? '') ?? 0;
      if ((id >= 14 && id <= 22) ||
          (id >= 27 && id <= 36) ||
          (id >= 45 && id <= 47) ||
          (id >= 50 && id <= 58)) {
        return true;
      }
      final code = (custom[id] ?? '')
          .replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]|\\.'), '')
          .toLowerCase();
      return RegExp(r'[ymdhs]').hasMatch(code);
    }

    final sheets =
        zip.files.where((f) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final out = StringBuffer();
    for (final sheet in sheets.take(5)) {
      final doc = XmlDocument.parse(utf8.decode(sheet.content, allowMalformed: true));
      out.writeln('## ${sheet.name.split('/').last.replaceAll('.xml', '')}');
      var rows = 0;
      for (final row in doc.findAllElements('row')) {
        if (rows++ >= _maxSheetRows) break;
        final cells = <int, String>{};
        for (final c in row.findElements('c')) {
          final col = _columnIndex(c.getAttribute('r') ?? '');
          final t = c.getAttribute('t');
          final v = c.getElement('v')?.innerText ?? '';
          String value;
          if (t == 's') {
            value = shared.elementAtOrNull(int.tryParse(v) ?? -1) ?? '';
          } else if (t == 'inlineStr') {
            value = c.findAllElements('t').map((e) => e.innerText).join();
          } else if (t == null || t == 'n') {
            final n = double.tryParse(v);
            value = n != null && isDateStyle(int.tryParse(c.getAttribute('s') ?? '') ?? -1)
                ? _excelDate(n)
                : v;
          } else {
            value = v;
          }
          if (col >= 0) cells[col] = value.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
        }
        if (cells.values.every((v) => v.isEmpty)) continue;
        final last = cells.keys.reduce((a, b) => a > b ? a : b);
        out.writeln([for (var i = 0; i <= last; i++) cells[i] ?? ''].join('\t'));
      }
    }
    return out.toString();
  }

  static int _columnIndex(String ref) {
    final letters = RegExp(r'^[A-Za-z]+').firstMatch(ref)?.group(0)?.toUpperCase();
    if (letters == null) return -1;
    var n = 0;
    for (final r in letters.codeUnits) {
      n = n * 26 + (r - 64);
    }
    return n - 1;
  }

  /// Excel stores dates as days since 1899-12-30 and times as a fraction of a day.
  static String _excelDate(double serial) {
    final days = serial.floor();
    final minutes = ((serial - days) * 1440).round();
    final time =
        '${(minutes ~/ 60 % 24).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
    if (days == 0) return time;
    final d = DateTime.utc(1899, 12, 30).add(Duration(days: days));
    final date =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return minutes == 0 ? date : '$date $time';
  }
}
