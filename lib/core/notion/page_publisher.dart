import '../../features/editor/models/template_model.dart';
import 'block_mapper.dart';
import 'database_mapper.dart';
import 'notion_client.dart';
import 'notion_exceptions.dart';

class PublishResult {
  final String pageId;
  final String? url;

  /// Things that didn't work but didn't stop the page being created, such as
  /// part of a progress bar. Shown to the user.
  final List<String> warnings;
  const PublishResult(this.pageId, this.url, {this.warnings = const []});
}

/// Where the template goes.
enum PublishMode {
  /// A new page inside the chosen page. Nothing existing is touched.
  newPage,

  /// The template's blocks are added to the end of the chosen page.
  append,

  /// The template's blocks are added to the chosen page, then the page's old
  /// content is moved to Notion's trash (it can be restored there).
  replace,
}

/// Thrown when the page exists but some of its content failed to publish.
class PartialPublishException extends NotionException {
  final PublishResult page;

  /// Blocks (or database rows) that were not created.
  final int missingBlocks;
  PartialPublishException(this.page, this.missingBlocks, String cause, {bool created = true})
    : super(
        '${created ? 'The page was created, but' : 'Part of the content was added, but'} '
        '$missingBlocks items are missing: $cause',
      );
}

typedef ProgressCallback = void Function(String status);

/// A shared counter, so a failure partway through a step still reports an accurate number.
class _Count {
  int n;
  _Count(this.n);
}

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

  /// Publishes [t]. With [PublishMode.newPage], [targetId] is the page to create
  /// it inside; otherwise it is the existing page to write to. [updateDetails]
  /// also sets that page's title, icon and cover from the template.
  Future<PublishResult> publish(
    Template t,
    String targetId, {
    PublishMode mode = PublishMode.newPage,
    bool updateDetails = false,
    String? targetUrl,
    ProgressCallback? onProgress,
  }) async {
    final existing = mode != PublishMode.newPage;
    final steps = _steps(t.blocks);

    // A new page is created with the first run of blocks; an existing page gets everything appended.
    var firstChunks = <List<Json>>[];
    var rest = steps;
    if (!existing && steps.isNotEmpty && steps.first is List<TemplateBlock>) {
      firstChunks = chunkNotionBlocks(blocksToNotion(steps.first as List<TemplateBlock>));
      rest = steps.sublist(1);
    }

    // Items still to create, for an honest "N missing" message on failure.
    final left = _Count(
      [
        for (final s in steps)
          if (s is TemplateBlock)
            1 + s.rows.length + (s.progressColumn != null ? 1 : 0)
          else
            blocksToNotion(s as List<TemplateBlock>).length,
      ].fold<int>(0, (a, b) => a + b),
    );

    final warnings = <String>[];
    final String pageId;
    String? url;
    var oldContent = <BlockSummary>[];
    if (existing) {
      pageId = targetId;
      url = targetUrl;
      if (mode == PublishMode.replace) {
        // Remember what is there now; it is removed only after the new content is safely in place.
        onProgress?.call('Reading the page…');
        oldContent = await client.listChildren(pageId);
      }
      if (updateDetails) {
        onProgress?.call('Updating the page title…');
        await client.updatePage(pageId, pageDetailsPayload(t));
      }
      if (url == null) {
        try {
          url = (await client.getPage(pageId))['url'] as String?;
        } on NotionException {
          // The link is only a convenience.
        }
      }
    } else {
      onProgress?.call('Creating page…');
      final page = await client.createPage(
        pagePayload(t, targetId, firstChunks.isEmpty ? [] : firstChunks.first),
      );
      pageId = page['id'] as String;
      url = page['url'] as String?;
      if (firstChunks.isNotEmpty) left.n -= firstChunks.first.length;
    }
    PublishResult result() => PublishResult(pageId, url, warnings: List.of(warnings));

    try {
      for (final chunk in firstChunks.skip(1)) {
        await client.appendChildren(pageId, chunk);
        left.n -= chunk.length;
      }
      for (final step in rest) {
        if (step is TemplateBlock) {
          await _publishDatabase(step, pageId, left, warnings, onProgress);
        } else {
          onProgress?.call('Adding content…');
          for (final chunk in chunkNotionBlocks(blocksToNotion(step as List<TemplateBlock>))) {
            await client.appendChildren(pageId, chunk);
            left.n -= chunk.length;
          }
        }
      }
    } on NotionException catch (e) {
      throw PartialPublishException(result(), left.n, e.message, created: !existing);
    }

    if (oldContent.isNotEmpty) await _removeOld(oldContent, warnings, onProgress);
    return result();
  }

  /// Moves the page's previous content to Notion's trash, one block at a time.
  /// A block that can't be removed is reported but doesn't stop the others.
  Future<void> _removeOld(
    List<BlockSummary> old,
    List<String> warnings,
    ProgressCallback? onProgress,
  ) async {
    var failed = 0;
    String? reason;
    for (var i = 0; i < old.length; i++) {
      onProgress?.call('Removing the old content (${i + 1}/${old.length})…');
      try {
        await client.deleteBlock(old[i].id);
      } on NotionException catch (e) {
        if (e.isAuthProblem || e.code == 'restricted_resource') rethrow;
        failed++;
        reason ??= e.message;
      }
    }
    if (failed > 0) {
      warnings.add(
        'Your new content was added, but $failed of ${old.length} old blocks could not be removed '
        '($reason). You can delete them in Notion.',
      );
    }
  }

  /// Creates one database block (and its progress bar, if it has one),
  /// counting down [left] as items are created. Problems with the progress bar
  /// are added to [warnings] rather than thrown, so the rest of the page still
  /// publishes.
  Future<void> _publishDatabase(
    TemplateBlock db,
    String pageId,
    _Count left,
    List<String> warnings,
    ProgressCallback? onProgress,
  ) async {
    final hasProgress = db.progressColumn != null;

    // The progress table goes first so it appears above the tasks.
    String? progressDbId;
    if (hasProgress) {
      onProgress?.call('Creating progress bar…');
      progressDbId =
          (await client.createDatabase(progressDatabasePayload(db, pageId)))['id'] as String;
      left.n -= 1;
    }

    onProgress?.call('Creating database "${db.text}"…');
    final created = await client.createDatabase(databasePayload(db, pageId));
    final dbId = created['id'] as String;
    left.n -= 1;

    final taskIds = <String>[];
    for (var i = 0; i < db.rows.length; i++) {
      onProgress?.call('Adding rows to "${db.text}" (${i + 1}/${db.rows.length})…');
      final row = await client.createPage(rowPayload(db, db.rows[i], dbId));
      taskIds.add(row['id'] as String);
      left.n -= 1;
    }

    if (progressDbId != null) {
      onProgress?.call('Linking the progress bar…');
      await _linkProgress(db, progressDbId, dbId, taskIds, warnings);
    }
  }

  Future<void> _linkProgress(
    TemplateBlock db,
    String progressDbId,
    String tasksDbId,
    List<String> taskIds,
    List<String> warnings,
  ) async {
    final name = db.text.trim().isEmpty ? 'The tasks' : '"${db.text.trim()}"';
    const hint = 'The checkboxes still work; you can add a progress bar by hand in Notion.';
    try {
      await client.updateDatabase(progressDbId, progressRelationPatch(tasksDbId));
      await client.updateDatabase(progressDbId, progressRollupsPatch(db));
    } on NotionException catch (e) {
      warnings.add(
        '$name was created, but its progress bar could not be linked to the tasks (${e.message}). $hint',
      );
      return;
    }

    // The visual bar is a formula; it is optional, so failing is only a warning.
    var barAdded = false;
    for (final expr in progressFormulaExpressions()) {
      try {
        await client.updateDatabase(progressDbId, progressFormulaPatch(expr));
        barAdded = true;
        break;
      } on NotionException catch (e) {
        if (e.isAuthProblem) rethrow;
      }
    }
    if (!barAdded) {
      warnings.add(
        'The progress table for $name shows Done, Total and a Percent column, but Notion would not accept the '
        'text bar column. In Notion, click the Percent column and choose Show as > Bar for a visual bar.',
      );
    }

    try {
      await client.createPage(progressRowPayload(db, progressDbId, taskIds));
    } on NotionException catch (e) {
      warnings.add(
        'The progress table for $name was created, but its row could not be added (${e.message}).',
      );
    }
  }
}
