/// Keep in sync with `version:` in pubspec.yaml (a test checks this).
const appVersion = '1.0.0';

class NotionConstants {
  static const String apiVersion = '2022-06-28';
  static const String baseUrl = 'https://api.notion.com/v1';
  static const String integrationsUrl = 'https://www.notion.so/my-integrations';

  /// Notion API limits.
  static const int maxChildrenPerRequest = 100;
  static const int maxBlocksPerRequest = 500; // API hard limit is 1000
  static const int maxRichTextLength = 2000;

  static const List<String> textColors = [
    'default',
    'gray',
    'brown',
    'orange',
    'yellow',
    'green',
    'blue',
    'purple',
    'pink',
    'red',
  ];
}

/// A user-facing theme: one pick maps to coordinated Notion colors.
class TemplateTheme {
  final String name;
  final String heading;
  final String callout;
  const TemplateTheme(this.name, this.heading, this.callout);

  static const List<TemplateTheme> all = [
    TemplateTheme('Classic', 'default', 'gray_background'),
    TemplateTheme('Ocean', 'blue', 'blue_background'),
    TemplateTheme('Forest', 'green', 'green_background'),
    TemplateTheme('Sunset', 'orange', 'orange_background'),
    TemplateTheme('Blossom', 'pink', 'pink_background'),
    TemplateTheme('Royal', 'purple', 'purple_background'),
  ];
}

/// Embed presets that are known to embed in Notion. Users can also paste any
/// https link (clock, weather and calendar widget sites give you one) and save
/// their favorites in the app.
class WidgetPreset {
  final String name;
  final String url;
  const WidgetPreset(this.name, this.url);

  static const List<WidgetPreset> all = [
    WidgetPreset('YouTube lo-fi (music player)', 'https://www.youtube.com/watch?v=jfKfPfyJRdk'),
    WidgetPreset(
      'Spotify playlist (music player)',
      'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
    ),
  ];
}
