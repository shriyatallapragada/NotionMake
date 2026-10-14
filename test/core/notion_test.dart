import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notion_make/core/notion/block_mapper.dart';
import 'package:notion_make/core/notion/notion_client.dart';
import 'package:notion_make/core/notion/notion_exceptions.dart';
import 'package:notion_make/core/notion/page_publisher.dart';
import 'package:notion_make/features/editor/models/template_model.dart';

http.Response _json(int code, Object body, [Map<String, String>? h]) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json', ...?h});

void main() {
  group('block mapper', () {
    test('page title uses the nested {title: {title: [...]}} shape', () {
      final p = pagePayload(const Template(title: 'Hi'), 'parent', []);
      expect(p['properties']['title']['title'][0]['text']['content'], 'Hi');
      expect(p['parent'], {'page_id': 'parent'});
    });

    test('long text is split at 2000 chars', () {
      expect(richText('a' * 4500).length, 3);
      expect(richText(''), isEmpty);
    });

    test('maps each block type', () {
      expect(blockToNotion(TemplateBlock.heading('x', level: 2)).single['type'], 'heading_2');
      expect(blockToNotion(TemplateBlock.divider()).single['type'], 'divider');
      expect(
        blockToNotion(TemplateBlock.embed(' https://a.b ')).single['embed']['url'],
        'https://a.b',
      );
      expect(blockToNotion(TemplateBlock.quote('q')).single['type'], 'quote');
    });

    test('list blocks become one Notion block per non-empty line', () {
      final todo = blockToNotion(TemplateBlock.todo('a\n\n b \n'));
      expect(todo.map((b) => b['type']), ['to_do', 'to_do']);
      expect(todo[1]['to_do']['rich_text'][0]['text']['content'], 'b');
      expect(todo[0]['to_do']['checked'], false);
      expect(blockToNotion(TemplateBlock.bullet('x\ny')).length, 2);
    });

    test('chunking', () {
      for (final (n, chunks) in [(0, 0), (100, 1), (101, 2), (250, 3)]) {
        expect(chunkBlocks(List.filled(n, 0)).length, chunks);
      }
    });
  });

  group('client', () {
    test('maps 404 to a friendly share-with-integration message', () async {
      final c = NotionClient(
        't',
        httpClient: MockClient(
          (_) async => _json(404, {'code': 'object_not_found', 'message': 'nope'}),
        ),
      );
      expect(
        c.getBotName(),
        throwsA(
          isA<NotionException>().having((e) => e.message, 'message', contains('Connections')),
        ),
      );
    });

    test('retries on 429 then succeeds', () async {
      var calls = 0;
      final c = NotionClient(
        't',
        retryBase: Duration.zero,
        httpClient: MockClient(
          (_) async => ++calls < 3
              ? _json(429, {'code': 'rate_limited'}, {'retry-after': '0'})
              : _json(200, {'name': 'Bot'}),
        ),
      );
      expect(await c.getBotName(), 'Bot');
      expect(calls, 3);
    });
  });

  group('publisher', () {
    test('creates page then appends overflow chunks', () async {
      final reqs = <String>[];
      final c = NotionClient(
        't',
        httpClient: MockClient((r) async {
          reqs.add('${r.method} ${r.url.path}');
          return _json(200, {'id': 'page1', 'url': 'https://notion.so/p'});
        }),
      );
      final t = Template(title: 'T', blocks: List.generate(150, (_) => TemplateBlock.divider()));
      final res = await PagePublisher(c).publish(t, 'parent');
      expect(res.url, 'https://notion.so/p');
      expect(reqs, ['POST /v1/pages', 'PATCH /v1/blocks/page1/children']);
    });

    test('reports partial failure with the created page', () async {
      var n = 0;
      final c = NotionClient(
        't',
        httpClient: MockClient((_) async {
          return ++n == 1
              ? _json(200, {'id': 'p', 'url': 'u'})
              : _json(400, {'code': 'validation_error', 'message': 'bad'});
        }),
      );
      final t = Template(title: 'T', blocks: List.generate(130, (_) => TemplateBlock.divider()));
      expect(
        PagePublisher(c).publish(t, 'x'),
        throwsA(isA<PartialPublishException>().having((e) => e.missingBlocks, 'missing', 30)),
      );
    });
  });
}
