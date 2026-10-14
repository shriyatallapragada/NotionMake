import '../../features/editor/models/template_model.dart';
import 'block_mapper.dart';
import 'database_mapper.dart';
import 'notion_client.dart';
import 'notion_exceptions.dart';

class PublishResult {
  final String pageId;
  final String? url;
  const PublishResult(this.pageId, this.url);
}

/// Thrown when the page exists but some of its content failed to publish.
class PartialPublishException extends NotionException {
  final PublishResult page;

  /// Blocks (or database rows) that were not created.
  final int missingBlocks;
  PartialPublishException(this.page, this.missingBlocks, String cause)
    : super('The page was created, but $missingBlocks items are missing: $cause');
}

typedef ProgressCallback = void Function(String status);

/// Publishes a template: the page first, then its content in order. Databases
/// are created as children of the page, and blocks below a database are
/// appended afterwards, so the page keeps the order the user designed.
class PagePublisher {
  final NotionClient client;
  const PagePublisher(this.client);

  /// Splits the page into runs of ordinary blocks and single database blocks.
  static List<Object> _steps(List<TemplateBlock> blocks) {
    final steps = <Object>[];
    var run = <TemplateBlock>[];
    for (final b in blocks) {
      if (b.type == BlockType.database) {
        if (run.isNotEmpty) steps.add(run);
        run = [];
        steps.add(b);
      } else {
        run.add(b);
      }
    }
    if (run.isNotEmpty) steps.add(run);
    return steps;
  }

  Future<PublishResult> publish(Template t, String parentId, {ProgressCallback? onProgress}) async {
    final steps = _steps(t.blocks);

    var firstChunks = <List<Json>>[];
    var rest = steps;
    if (steps.isNotEmpty && steps.first is List<TemplateBlock>) {
      firstChunks = chunkNotionBlocks(blocksToNotion(steps.first as List<TemplateBlock>));
      rest = steps.sublist(1);
    }

    // Items still to create, for an honest "N missing" message on failure.
    var left = [
      for (final s in steps)
        if (s is TemplateBlock)
          1 + s.rows.length
        else
          blocksToNotion(s as List<TemplateBlock>).length,
    ].fold<int>(0, (a, b) => a + b);

    onProgress?.call('Creating page…');
    final page = await client.createPage(
      pagePayload(t, parentId, firstChunks.isEmpty ? [] : firstChunks.first),
    );
    final result = PublishResult(page['id'] as String, page['url'] as String?);
    if (firstChunks.isNotEmpty) left -= firstChunks.first.length;

    try {
      for (final chunk in firstChunks.skip(1)) {
        await client.appendChildren(result.pageId, chunk);
        left -= chunk.length;
      }
      for (final step in rest) {
        if (step is TemplateBlock) {
          onProgress?.call('Creating database "${step.text}"…');
          final db = await client.createDatabase(databasePayload(step, result.pageId));
          left -= 1;
          final dbId = db['id'] as String;
          for (var i = 0; i < step.rows.length; i++) {
            onProgress?.call('Adding rows to "${step.text}" (${i + 1}/${step.rows.length})…');
            await client.createPage(rowPayload(step, step.rows[i], dbId));
            left -= 1;
          }
        } else {
          onProgress?.call('Adding content…');
          for (final chunk in chunkNotionBlocks(blocksToNotion(step as List<TemplateBlock>))) {
            await client.appendChildren(result.pageId, chunk);
            left -= chunk.length;
          }
        }
      }
    } on NotionException catch (e) {
      throw PartialPublishException(result, left, e.message);
    }
    return result;
  }
}
