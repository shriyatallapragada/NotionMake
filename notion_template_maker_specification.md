# Project Specification & Architecture Blueprint
## Local Cross-Platform Notion Template Maker (Flutter)

---

## 1. Project Overview
* **Objective:** Build a local desktop and mobile application using **Flutter** that allows users to visually configure custom Notion page templates (including color themes, layouts, structured blocks, and free online widgets like clocks, weather, or calendars) and instantly push them to their **Free Notion Account** via the official Notion REST API.
* **Target Platforms:** Cross-platform desktop (Windows, macOS, Linux) and mobile (Android, iOS).
* **Key Constraint:** Runs entirely locally on the user's device with zero external server dependencies, utilizing local secure storage for API keys.

---

## 2. Technical Stack & Dependencies
* **Framework:** Flutter (Dart)
* **State Management:** `flutter_riverpod`
* **Local Secure Storage:** `flutter_secure_storage` (stores the Notion Integration Token in native encrypted keychain/Credential Manager)
* **Networking:** `http` package for REST API communication with Notion.
* **UI Responsiveness:** `LayoutBuilder` / `MediaQuery` to dynamically adjust layouts between wide desktop windows and compact mobile screens.

### Dependencies (`pubspec.yaml`)
Add the following package dependencies to your Flutter configuration:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  http: ^1.2.0
  flutter_secure_storage: ^9.0.0
```

---

## 3. Recommended Project Directory Structure
```text
lib/
│-- core/
│   │-- constants.dart         # Notion API endpoints, header templates, color maps
│   `-- secure_storage.dart    # Helper for reading/writing Notion API token securely
│
│-- features/
│   `-- template_builder/
│       │-- models/
│       │   `-- template_model.dart    # Data structures for user selections & blocks
│       │-- providers/
│       │   `-- template_provider.dart # Riverpod state manager for inputs & API status
│       │-- services/
│       │   `-- notion_service.dart    # Converts model to JSON & handles POST /v1/pages
│       `-- screens/
│           │-- settings_screen.dart   # Screen to input and save Integration Token
│           `-- builder_screen.dart    # Main builder UI (Desktop/Mobile responsive)
│
`-- main.dart
```

---

## 4. Core Implementation Components

### A. Core Constants & Notion Block Mappings (`core/constants.dart`)
Notion uses specific color keys and block types. Define these cleanly so the app can map user-friendly color choices to Notion API block properties:

```dart
class NotionConstants {
  static const String apiVersion = '2022-06-28';
  static const String baseUrl = 'https://api.notion.com/v1';

  // Supported Notion block background colors
  static const List<String> backgroundColors = [
    'default',
    'gray_background',
    'brown_background',
    'orange_background',
    'yellow_background',
    'green_background',
    'blue_background',
    'purple_background',
    'pink_background',
    'red_background',
  ];
}
```

### B. Notion API Service Layer (`features/template_builder/services/notion_service.dart`)
This service takes the user's configuration and compiles it into a JSON block payload accepted by Notion's `POST /v1/pages` endpoint.

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';

class NotionService {
  final String integrationToken;

  NotionService({required this.integrationToken});

  Future<Map<String, dynamic>> createPage({
    required String parentPageId,
    required String title,
    required String headerColor,
    required String calloutText,
    required String widgetUrl,
  }) async {
    final url = Uri.parse('${NotionConstants.baseUrl}/pages');

    final payload = {
      "parent": {"page_id": parentPageId},
      "properties": {
        "title": [
          {"type": "text", "text": {"content": title}}
        ]
      },
      "children": [
        // Heading Block with Custom Color
        {
          "object": "block",
          "type": "heading_1",
          "heading_1": {
            "rich_text": [{"type": "text", "text": {"content": title}}],
            "color": headerColor
          }
        },
        // Callout Block for Quick Notes
        {
          "object": "block",
          "type": "callout",
          "callout": {
            "rich_text": [{"type": "text", "text": {"content": calloutText}}],
            "icon": {"emoji": "✨"},
            "color": "gray_background"
          }
        },
        // Divider
        {
          "object": "block",
          "type": "divider",
          "divider": {}
        },
        // Widget Embed Block
        {
          "object": "block",
          "type": "embed",
          "embed": {
            "url": widgetUrl
          }
        }
      ]
    };

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $integrationToken',
        'Content-Type': 'application/json',
        'Notion-Version': NotionConstants.apiVersion,
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      return {'success': true, 'data': jsonDecode(response.body)};
    } else {
      return {'success': false, 'error': response.body};
    }
  }
}
```

### C. Responsive UI Layout Strategy
The user interface implements an adaptive layout using `LayoutBuilder`:
* **Desktop View (> 800px width):** Displays a two-pane layout where the left pane contains form controls (Page Title, Parent ID, Color Selector, Widget URL) and the right pane displays a real-time visual preview of the page structure.
* **Mobile View (<= 800px width):** Stacks the form inputs and preview vertically inside a single scrollable view with tab switching or expandable cards.

---

## 5. Master Prompt Strategy for Code Generation
When passing this blueprint to Claude to generate all code files in one command, use the following prompt:

> *"Using the architectural blueprint provided above, please generate the complete, production-ready code files for this Flutter local Notion Template Maker app. Please include:*
> 1. `core/secure_storage.dart` *for saving and reading the Notion token.*
> 2. `features/template_builder/services/notion_service.dart` *for handling the API payload construction.*
> 3. `features/template_builder/providers/template_provider.dart` *using Riverpod to manage state.*
> 4. `features/template_builder/screens/builder_screen.dart` *with a responsive design supporting both desktop and mobile layouts.*
> 
> *Ensure clean code, proper null safety, and clear comments explaining how to test it locally."*