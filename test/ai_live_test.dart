// Optional integration test against a real local Ollama.
// Run with:
//   OLLAMA_LIVE=1 [OLLAMA_MODEL=qwen3.5:9b] [OLLAMA_PROMPT="..."] flutter test test/ai_live_test.dart
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notion_make/core/constants.dart';
import 'package:notion_make/core/notion/template_validation.dart';
import 'package:notion_make/features/ai/attachments.dart';
import 'package:notion_make/features/ai/ollama_client.dart';
import 'package:notion_make/features/ai/template_ai.dart';
import 'package:notion_make/features/editor/models/template_model.dart';

const _timetable = '''
Day,Time,Subject,Room
Monday,09:00,Maths,B12
Monday,11:00,Physics,Lab 2
Tuesday,10:00,English,A4
Wednesday,09:00,Maths,B12
Thursday,13:00,Chemistry,Lab 1
Friday,10:00,History,C7
''';

void main() {
  final live = Platform.environment['OLLAMA_LIVE'] == '1';
  final model = Platform.environment['OLLAMA_MODEL'] ?? 'qwen3.5:9b';
  final prompt =
      Platform.environment['OLLAMA_PROMPT'] ??
      'Make me a weekly study planner from my timetable. Add a lo-fi music widget.';

  test(
    'a real model turns a timetable into a valid template',
    () async {
      final outcome = await TemplateAi(OllamaClient(OllamaClient.defaultHost)).generate(
        model: model,
        prompt: prompt,
        widgets: [for (final p in WidgetPreset.all) (name: p.name, url: p.url)],
        attachments: Platform.environment['OLLAMA_NODOC'] == '1'
            ? const []
            : [AiAttachment.text('timetable.csv', _timetable)],
        onStatus: (_) {},
      );
      final t = outcome.page.template;
      stdout.writeln(
        '--- ${outcome.took.inSeconds}s, ${outcome.promptTokens} in / ${outcome.outputTokens} out',
      );
      stdout.writeln(
        'RESULT "${t.title}" ${t.icon}: ${t.blocks.map((b) => b.type.name).join(", ")}',
      );
      for (final b in t.blocks.where(
        (b) => b.type == BlockType.embed || b.type == BlockType.callout,
      )) {
        stdout.writeln('  ${b.type.name}: ${b.text}');
      }
      final todos = t.blocks.where((b) => b.type == BlockType.todo).length;
      stdout.writeln('separate to-do blocks: $todos');
      stdout.writeln('WARNING: ${outcome.warning}');
      expect(validateTemplate(t), isNull);
    },
    skip: live ? false : 'set OLLAMA_LIVE=1 to run against a local Ollama',
  );
}
