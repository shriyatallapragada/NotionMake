# NotionMake: Revised Blueprint & Build Plan

A local Flutter app where you pick a template, tweak it visually, and push it into your Notion workspace in one click. No backend.

This supersedes `notion_template_maker_specification.md`. Section 1 lists what changed and why.

---

## 1. Problems in the original spec (and fixes)

| # | Problem | Fix |
|---|---------|-----|
| 1 | **Bug:** `"properties": {"title": [ ... ]}` is invalid for `POST /v1/pages`. It must be `{"title": {"title": [ ... ]}}`. The page would be rejected with a 400. | Corrected in the payload builder (section 5). |
| 2 | The heading block repeats the page title, so every page shows the title twice. | The title is a page property only. The heading is optional content. |
| 3 | The user must paste a **Parent Page ID**. That is the biggest usability barrier. | Use `POST /v1/search` to list pages the integration can see, and let the user pick one from a searchable list. |
| 4 | The "just paste a token" flow isn't explained. Most failures will be `object_not_found` because the parent page was never shared with the integration. | Guided onboarding with a "Test connection" button and a plain-English error for each failure (section 6). |
| 5 | One hard-coded page shape (heading, callout, divider, embed). It's a form, not a template maker. | Block-based model: an ordered list of typed blocks the user adds, reorders, and edits (section 4). |
| 6 | "Free online widgets" are left vague, and widget hosts come and go (Indify shut down, for example). | A user-editable **widget catalog** (JSON) with presets, plus "paste any embed URL". No provider is hard-coded. Embeds are validated as `https`. |
| 7 | Ignores Notion API limits: 100 children per request, 2 levels of nesting per request, ~3 requests/second, 2000 chars per rich-text item. | `BlockChunker` and a retry-with-backoff client on 429 (section 5). |
| 8 | Returns `Map<String, dynamic>` with `success` flags. | Typed `Result` / exceptions (`NotionException` subclasses). |
| 9 | Only the `200` status is checked, and the error body is dumped raw. | Parse Notion's `{code, message}` and map to friendly messages. |
| 10 | Missing page extras Notion supports on create: **icon** and **cover**. | Added to the model and UI. |
| 11 | No persistence of the user's own templates. | Local JSON storage (`path_provider`) with import/export of `.notiontpl.json` files. |
| 12 | Linux/macOS secure-storage gotchas aren't mentioned. | Platform notes in section 8. |
| 13 | No tests, no CI, no success criteria. | Test strategy and per-phase "done" criteria below. |
| 14 | Original prompt asks for 4 files in one shot. | Phased plan with a working app after every phase. |

**Honest constraint:** Notion's OAuth needs a client secret, which means a server. That would break "no backend", so the app uses an **internal integration token** (user-created, one-time setup). Onboarding is designed to make that painless. Also, the API **cannot** create Notion's native "template buttons" or duplicate-able template gallery items. The app creates ordinary pages and databases pre-filled with structure, which the user can then duplicate inside Notion.

---

## 2. Product goals

1. **First push in under 3 minutes** from a fresh install, including token setup.
2. **Zero IDs, zero JSON.** The user never types a page ID or sees a payload.
3. **WYSIWYG-ish preview** that is close enough to Notion to trust.
4. **Safe.** Never overwrites or deletes anything. It only creates new pages under the parent the user chose.
5. **Local only.** Token in the OS keychain, templates on disk, and the only network calls go to `api.notion.com` and the user's own embed URLs.

Non-goals (v1): editing existing pages, syncing back from Notion, accounts, cloud storage.

---

## 3. Tech stack

| Concern | Choice | Why |
|---------|--------|-----|
| Framework | Flutter 3.x / Dart 3 | Required for desktop and mobile |
| State | `flutter_riverpod` (+ `riverpod_annotation`) | Per spec, testable |
| Storage (secret) | `flutter_secure_storage` | Token in the keychain |
| Storage (data) | `path_provider` + JSON files | Simple and exportable; no DB needed |
| HTTP | `http` with a thin `NotionClient` wrapper | Per spec; easy to mock |
| Models | `freezed` + `json_serializable` | Sealed block types, immutable edits, undo |
| Routing | `go_router` | Adaptive navigation |
| Reorder UI | `ReorderableListView` (built in) | No extra dependency |
| Colors | `flex_color_picker` (optional) | Only if custom swatches are needed |
| File import/export | `file_picker`, `share_plus` | Share `.notiontpl.json` |
| Testing | `flutter_test`, `mocktail`, golden tests | HTTP mocking and preview checks |

---

## 4. Domain model

```
Template
  id, name, description, icon (emoji), coverUrl?, themeColor
  blocks: List<TemplateBlock>

TemplateBlock (sealed)
  HeadingBlock(level 1-3, text, color)
  ParagraphBlock(text, color)
  CalloutBlock(text, emoji, color)
  TodoBlock(items[])
  BulletListBlock(items[])
  QuoteBlock(text)
  DividerBlock
  EmbedBlock(url, caption?)           // widgets: clock, weather, calendar...
  ColumnsBlock(columns: List<List<TemplateBlock>>)   // 2-3 columns
  ToggleBlock(title, children)
  DatabaseBlock(title, properties[], view)   // phase 4
```

Everything is plain data, serializable to JSON, and independent of Flutter UI. That keeps it unit-testable and shareable.

**Built-in starter templates** (shipped as JSON assets): Daily Planner, Weekly Review, Habit Tracker, Project Dashboard, Reading List, Meeting Notes, Student Hub. Each has a theme color and a widget or two.

**Themes:** one pick (for example "Ocean") maps to coordinated Notion colors for headings, callouts, and quotes. Notion colors are limited to its fixed set, so a theme is just a mapping `{heading: blue, callout: blue_background, ...}`.

---

## 5. Notion integration layer

```
lib/core/notion/
  notion_client.dart       // auth headers, retry/backoff on 429/5xx, timeouts
  notion_exceptions.dart   // Unauthorized, NotShared, RateLimited, Validation, Network
  block_mapper.dart        // TemplateBlock -> Notion JSON
  block_chunker.dart       // splits >100 children, appends rest via PATCH /blocks/{id}/children
  rich_text.dart           // splits text into <=2000-char segments
  page_publisher.dart      // orchestrates: create page, then append remaining chunks
```

**Corrected create-page payload:**

```json
{
  "parent": { "page_id": "<picked from search>" },
  "icon":   { "type": "emoji", "emoji": "📅" },
  "cover":  { "type": "external", "external": { "url": "https://..." } },
  "properties": {
    "title": { "title": [ { "type": "text", "text": { "content": "My Planner" } } ] }
  },
  "children": [ /* first <=100 blocks */ ]
}
```

**Endpoints used**

| Purpose | Call |
|---------|------|
| Validate token | `GET /v1/users/me` |
| List/search parents | `POST /v1/search` with `filter: {property: "object", value: "page"}`, paginated via `start_cursor` |
| Create page | `POST /v1/pages` |
| Append overflow/nested blocks | `PATCH /v1/blocks/{id}/children` |
| Databases (phase 4) | `POST /v1/databases`, then `POST /v1/pages` per sample row |

**Rules baked into the layer**
- Pin `Notion-Version: 2022-06-28` in one constant.
- Max 100 blocks per request, so chunk and append the rest.
- Max 2 nesting levels per request, so deeper trees are appended in follow-up calls.
- Retry on `429` honoring `Retry-After`; cap retries at 3; stay under about 3 req/s.
- Return the created page's `url` so the UI can offer **Open in Notion**.
- Partial-failure handling: if chunk 2 fails, report "page created, N blocks missing" with a retry button instead of failing silently.

---

## 6. UX design

### Onboarding (first run, 3 steps)
1. **Create an integration.** A button opens `notion.so/my-integrations`, with a 3-line illustrated checklist.
2. **Paste token.** "Test connection" calls `/users/me` and shows the workspace/bot name on success.
3. **Share a page.** Explain "open a page, then `...` > Connections > add your integration". A "Refresh" button re-runs search until at least one page appears.

### Main flow
- **Gallery:** template cards (built-in + mine) with search.
- **Editor:** block list (add, drag to reorder, duplicate, delete, undo/redo) + live preview + a theme/icon/cover panel.
- **Publish sheet:** searchable list of destination pages, a summary ("12 blocks, 1 embed"), a **Publish** button, then progress, then **Open in Notion**.

### Layout
- **>= 900 px:** three panes (sidebar / editor / preview).
- **600-900 px:** two panes, with the preview in a toggleable side sheet.
- **< 600 px:** single column, bottom navigation (Templates / Editor / Preview), publish as a bottom sheet.

### Quality-of-life
- Friendly error copy mapped from Notion codes. For example, `object_not_found` becomes "Notion can't see that page. Share it with your integration."
- Autosave drafts; "Duplicate template"; import/export `.notiontpl.json`.
- Warn (don't block) when an embed URL isn't https or the provider is known to block iframes.
- Light/dark theme, keyboard shortcuts on desktop (Cmd/Ctrl+S, Cmd/Ctrl+Enter to publish), accessible labels and contrast.

---

## 7. Directory structure

```
lib/
  main.dart
  app.dart                      // MaterialApp.router, theme
  core/
    constants.dart
    secure_storage.dart
    notion/                     // see section 5
    result.dart
  features/
    onboarding/                 // token + connection test
    gallery/                    // template list, built-in assets
    editor/
      models/                   // freezed Template + TemplateBlock
      providers/                // editor state, undo stack
      widgets/                  // block editors, theme panel
      preview/                  // Notion-style renderer
    publish/                    // destination picker, progress, result
    settings/
  data/
    template_repository.dart    // local JSON persistence
    widget_catalog.dart         // embed presets (editable JSON)
assets/templates/*.json
test/
```

---

## 8. Platform notes

- **macOS:** add Keychain entitlement and `com.apple.security.network.client` to both `DebugProfile.entitlements` and `Release.entitlements`.
- **Linux:** needs `libsecret-1-dev` and a running keyring; show a clear message if it's unavailable.
- **Windows:** works out of the box (Credential Manager).
- **Android:** `minSdkVersion 23` for secure storage; internet permission in the release manifest.
- **iOS:** Keychain works by default; no extra network permissions.
- **Preview of embeds:** show a placeholder card (provider, URL), not a live webview. Notion renders the real embed, and this avoids `webview` dependencies on every platform.

---

## 9. Phased build plan

Each phase ends with something runnable.

### Phase 0: Scaffold (0.5 day)
- `flutter create --platforms=macos,windows,linux,android,ios notion_make`; add dependencies, lints, folder structure, CI (`flutter analyze`, `flutter test`).
- **Done when:** the app launches on at least one desktop target and one mobile target with an empty shell.

### Phase 1: Connect to Notion (1-2 days)
- `secure_storage.dart`, `NotionClient` (headers, retries, error mapping), onboarding screens, `/users/me` test, `/search` page listing.
- Unit tests with a mocked HTTP client for 200, 401, 404, 429.
- **Done when:** pasting a real token shows the workspace name and a list of shared pages.

### Phase 2: Minimal publish (1-2 days), the first usable app
- Model with Heading, Paragraph, Callout, Divider, Embed; `block_mapper`; corrected payload; destination picker; **Publish** and **Open in Notion**.
- One built-in template (Daily Planner).
- **Done when:** one click creates the page in a real free Notion workspace and it matches the preview.

### Phase 3: Editor and preview (3-4 days)
- Add, reorder, delete, duplicate blocks; undo/redo; theme, icon, and cover panel; responsive three-pane/one-pane layout; Notion-style preview renderer; autosave drafts.
- Golden tests for the preview.
- **Done when:** a non-technical tester can build and publish a custom page unaided.

### Phase 4: Rich blocks and templates (3-4 days)
- Columns, toggles, to-do/bullet lists, quotes; chunker for >100 blocks and deep nesting; widget catalog UI; 6 more built-in templates; template gallery with search; import/export.
- **Done when:** the Project Dashboard template (columns + embeds + 150 blocks) publishes completely.

### Phase 5: Databases (3-4 days, optional for v1)
- Property editor (title, select, status, date, checkbox, number); sample rows; templates such as Habit Tracker and Reading List.
- **Done when:** a Habit Tracker database with 3 sample rows is created correctly.

### Phase 6: Polish and release (2-3 days)
- Error-copy pass, accessibility pass, keyboard shortcuts, app icons, empty/loading states, release builds per platform, README with screenshots.
- **Done when:** the clean-install-to-first-push checklist passes on macOS plus one mobile device within 3 minutes.

**Rough total:** 2.5-3.5 weeks solo for phases 0-4 and 6; add about 1 week for databases.

---

## 10. Testing strategy

- **Unit:** every `TemplateBlock` maps to the expected JSON (snapshot files); the chunker splits 0, 100, 101, and 250 blocks correctly; rich-text splitter at 2000 chars; error mapping.
- **Integration (mocked HTTP):** the publish flow including a 429 retry and a partial failure.
- **Widget/golden:** the preview of each built-in template at desktop and mobile widths.
- **Manual smoke test:** a checklist run against a real free Notion workspace before each release. Use a dedicated test workspace, because the app only ever creates pages.

---

## 11. Risks

| Risk | Mitigation |
|------|-----------|
| Users get stuck at the token/sharing step | Guided onboarding, live "Test connection", targeted error text |
| Embed providers disappear or block iframes | Editable catalog, "paste any URL", warning text, no hard-coded host |
| Notion API changes | Version pinned in one place; contract tests against saved sample responses |
| Preview drifts from real Notion rendering | Keep the preview simple and label it "approximate"; golden tests |
| Secure storage unavailable (Linux) | Detect and explain; optional session-only token |

---

## 12. Next step

When you're ready, I can start on **Phase 0 and 1** (scaffold, secure storage, Notion client, onboarding) and get you to a working "connected to Notion" screen. If you'd rather go straight to the quickest visible result, I can do **Phases 0-2 together**, which gives you the first one-click publish.

---

## 13. Build status

| Phase | Status |
|-------|--------|
| 0 Scaffold | Done: Flutter project for macOS/Windows/Linux/Android/iOS, Riverpod, secure storage, entitlements |
| 1 Connect | Done: token storage, `NotionClient` (retry on 429, friendly errors), onboarding with connection test, page search |
| 2 Minimal publish | Done: block model/mapper (corrected payload), chunked publisher with partial-failure reporting, builder form + preview (responsive), destination picker, Open in Notion |
| 3 Editor | Done: block editor (add/reorder/duplicate/delete, 8 block types incl. to-do, bullet, quote), undo/redo with typing merge, autosave draft, color themes, template gallery (5 starters + blank) and "My templates", cover image, embed URL validation before publish |
| 4 Rich blocks | Done: columns (2-3) and toggles with nested editing, weight-aware request chunking (100 siblings / 500 total blocks), pre-publish validation, import/export of `.notiontpl.json` files, saved widget links, 3 new starter templates (Reading List, Weekly Planner, columns-based Project Dashboard) |
| 5 Databases | Done: database blocks (title, up to 20 typed columns: title/text/number/select/multi-select/checkbox/date/link; up to 50 sample rows), created as inline databases in the page in the designed order, publish progress ("Adding rows 2/3"), validation, 4 database starter templates (Task, Habit, Book, Expense trackers). Notion's API can't create "Status" columns, so Select is offered instead. |
| 10 Publish modes | Done: publish as a new page inside (default), add to the end of an existing page, or replace its content (new content written first, old content moved to Notion's trash only afterwards, with a confirmation naming how many blocks and sub-pages); optional title/icon/cover update; "Update <last page>" shortcut |
| 9 Database progress bars | Done: a database with a checkbox column can add a Notion-native progress bar (linked progress database with rollups for Done/Total/Percent plus a best-effort text-bar formula), live on every device; publisher treats bar problems as warnings so the page still publishes; AI and Task Tracker starter use it. Relation/rollup/formula requests follow the Notion API docs but are untested against a live workspace |
| 8 Built-in widgets | Done: 6 self-hosted widgets (clock, timer, countdown, calendar, progress, quote) in `docs/widgets`, served by GitHub Pages; validated link builder; editor chips + customize dialog; AI picks widget + settings (max 3, theme matched to the page) |
| 7 AI assistant | Done: local open-source AI via Ollama (no key, no caps, private). Recommended model Qwen 3.5 9B (also 4B and 2.5-7B), in-app model download with progress, streaming generation with Cancel, document import (PDF, DOCX, XLSX, CSV, TXT, ICS, images), widget allow-list with relevance filter, output repair/validation, "change my current page" mode, works with or without Ollama's structured-output engine |
| 6 Polish/release | Done: friendlier error wording and Reconnect/Try-again paths, catch-all so publishing never hangs, validation for title/icon/cover, empty-icon payload bug fixed, app menu + About, keyboard shortcuts, accessibility labels, empty-page hint, single-file theme (`lib/app_theme.dart`), app name + icon on all platforms, macOS minimum window size, README, CI workflow, release build `NotionMake.app` (45 MB) + zip |

Design note: columns and toggles hold simple blocks but can't be nested in each other. Notion allows 2 nesting levels per request, so this guarantees every page publishes in one valid request with no fragile follow-up calls.

`flutter analyze` is clean and 60 unit and widget tests pass. Not yet verified against a real Notion workspace.

Run it: `export PATH="$HOME/flutter/flutter/bin:$PATH"; flutter run -d macos` (requires full Xcode).
