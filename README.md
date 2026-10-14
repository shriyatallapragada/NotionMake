# NotionMake

Build Notion pages and databases visually, then publish them to your Notion workspace with one click.
Everything runs on your device: there is no server, and your Notion token is kept in your system keychain.

## What you can do

- Pick a **starter template** (Daily Planner, Weekly Review, Meeting Notes, Project Dashboard, Reading List,
  Weekly Planner, Student Hub, Task / Habit / Book / Expense trackers) or start blank.
- Edit the page as **blocks**: headings, text, callouts, to-do and bullet lists, quotes, dividers,
  widget embeds, **toggles**, **2-3 column layouts** and **databases** (typed columns plus sample rows).
- Reorder by dragging, **undo/redo**, apply a **color theme**, set an icon and cover image.
- See an approximate **live preview** next to the editor.
- **Save your own templates**, and import/export them as `.notiontpl.json` files.
- **Publish** into any page you choose from a searchable list. No page IDs or JSON.

- **Create with AI**: describe the page you want (and attach a timetable, syllabus or notes) and a free, open-source
  AI model running **on your own computer** builds it for you. See [AI assistant](#ai-assistant-free-and-private).

NotionMake only ever **creates new pages**. It never edits or deletes anything you already have.

## First-time setup (about 2 minutes)

1. Open <https://www.notion.so/my-integrations> and create a **New integration** (type: Internal).
   Make sure *Read content* and *Insert content* are enabled.
2. Copy the **Internal Integration Secret** and paste it into NotionMake's connect screen.
3. In Notion, open the page you want templates created under, click **...** > **Connections**, and add your
   integration. Pages that aren't shared with the integration won't appear in the app.

## AI assistant (free and private)

Press the ✨ button (or `⌘ Shift A`), describe the page you want, optionally attach documents, and press **Create template**.
The page appears in the editor, where you can change anything, and **Undo** reverts it in one click.

- **Runs on your computer.** It uses [Ollama](https://ollama.com) (free, open source) and open-weight models such as
  Qwen. There is no account, no API key, no token limit and no cost, and your requests and documents are never sent online.
- **One-time setup, guided in the app.** Install Ollama and open it, then choose a model in the AI sheet and press
  **Download** (the recommended *Qwen 3.5 · 9B* is a 6.6 GB download that needs about 8 GB of free memory;
  *Qwen 3.5 · 4B* is a 3.3 GB option for smaller computers). Already have other Ollama models? They show up in the list too.
- **Documents it can read:** PDF (with selectable text), Word `.docx`, Excel `.xlsx`, CSV/TSV, text, Markdown, calendar
  `.ics` and images (such as a timetable screenshot, using a vision model like Qwen 3.5). Up to 5 files, 10 MB each.
  Files are read on your computer; scanned PDFs have no text, so attach a screenshot instead.
- **Widgets.** It can embed a widget only if it is one of your saved widget links (or a link you typed in your request)
  *and* it matches what you asked for. Ask for a clock and have no clock link saved, and you get a "paste a clock link here" note.
- **Change an existing page.** Turn on *Change my current page instead of starting fresh* and describe the change.

Local models are smaller than cloud AIs: results are good for typical planners, timetables and trackers, but always glance
over the page before publishing. Generating takes roughly 20-60 seconds on a recent Mac; the first request also loads the model.

## Keyboard shortcuts

| Action | macOS | Windows / Linux |
|--------|-------|-----------------|
| Publish | `⌘ Enter` | `Ctrl+Enter` |
| Templates | `⌘ Shift T` | `Ctrl+Shift+T` |
| Create with AI | `⌘ Shift A` | `Ctrl+Shift+A` |

## Running from source

Requires [Flutter](https://docs.flutter.dev/get-started/install) (stable) and, for macOS builds, Xcode.

```bash
flutter pub get
flutter run -d macos        # or: windows, linux, android, ios
flutter test                # unit and widget tests
flutter analyze
dart format lib test        # project line width is 100
```

Release build for macOS:

```bash
flutter build macos --release
# result: build/macos/Build/Products/Release/NotionMake.app
```

The app is not code-signed. On first launch macOS may block it: right-click the app, choose **Open**, then confirm.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "No pages found" when publishing | Share a page with your integration (setup step 3), wait ~10 seconds, reopen the sheet. |
| "Notion rejected the token" | Copy the secret again from your integration page; make sure it is an *internal* integration. |
| Banner says the token couldn't be saved to the keychain | On macOS, open Keychain Access and make sure the **login** keychain is unlocked (or reset it). The app keeps working this session, but you will need to reconnect next time. |
| AI sheet says "Can't reach Ollama" | Open the Ollama app (or run `ollama serve`), then press *Check again*. |
| "needs a newer version of Ollama" | Update Ollama from ollama.com/download (or `brew upgrade ollama`) and restart it. |
| AI is slow or the computer struggles | Pick the lighter *Qwen 3.5 · 4B* model and close other big apps. |
| A widget block won't publish | Embed links must start with `https://`. Some sites forbid embedding; Notion then shows a plain link. |
| "Status" column missing in databases | Notion's API can't create Status columns. Use **Select** (e.g. To do, Doing, Done). |

## Limits (set by Notion's API)

- Toggles, columns and databases can only sit at the top level of a page (databases can't go inside columns).
- Databases: up to 20 columns and 50 sample rows (each row is one request, so publishing 50 rows takes ~15-20 s).
- Notion's native *template buttons* can't be created by any API. NotionMake creates ordinary pages and databases that you can duplicate inside Notion.

## Project layout

```
lib/
  app_theme.dart            the color palette and theme (change colors here)
  core/                     constants, secure storage, Notion client, mappers, validation, publisher
  data/                     local persistence (drafts, templates, saved widgets), template files
  features/
    onboarding/             connect screen
    editor/                 models, state (undo/redo, autosave), block editors, preview, templates sheet
    ai/                     local AI: Ollama client, document readers, prompt/schema, result repair, UI
    publish/                destination picker and publish flow
test/                       unit and widget tests
```
