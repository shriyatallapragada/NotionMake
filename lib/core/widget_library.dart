/// The built-in widget library: small web pages (clock, timer, countdown,
/// calendar, progress, quote) that Notion can embed. Every setting is
/// validated and normalised here, and the final link is always built by this
/// code, so neither the AI nor a typo can produce a broken or unsafe link.
library;

import 'constants.dart';
import 'notion/database_mapper.dart' show isValidDbDate;

enum OptionKind {
  choice,
  text,
  integer,
  flag,
  date,
  time,
  dateList,
  month,
  timezone,
  itemList,
  indexList,
}

class WidgetOption {
  final String name;
  final String label;
  final OptionKind kind;
  final List<String> choices;
  final int min;
  final int max;
  final bool required;

  /// The value the widget uses when the option is left out (shown in the editor).
  final String defaultValue;
  const WidgetOption(
    this.name,
    this.label,
    this.kind, {
    this.choices = const [],
    this.min = 0,
    this.max = 0,
    this.required = false,
    this.defaultValue = '',
  });

  /// Short description used in the AI prompt, e.g. "style (digital|analog)".
  String get promptHint => switch (kind) {
    OptionKind.choice => '$name (${choices.join('|')})',
    OptionKind.integer => '$name (number $min-$max)',
    OptionKind.flag => '$name (1|0)',
    OptionKind.date => '$name (YYYY-MM-DD)',
    OptionKind.time => '$name (HH:MM)',
    OptionKind.dateList => '$name (comma-separated YYYY-MM-DD dates)',
    OptionKind.month => '$name (YYYY-MM)',
    OptionKind.timezone => '$name (IANA zone such as Asia/Kolkata)',
    OptionKind.text => '$name (short text)',
    OptionKind.itemList => '$name (the tasks, separated by |, up to 30)',
    OptionKind.indexList => '$name (numbers of tasks already done, comma-separated)',
  };

  /// A cleaned value, or null if [raw] isn't acceptable for this option.
  String? normalize(String raw) {
    // Control characters are removed, except the newlines that separate tasks.
    final v = raw
        .replaceAll(
          kind == OptionKind.itemList ? RegExp(r'[\x00-\x09\x0B-\x1F]') : RegExp(r'[\x00-\x1F]'),
          '',
        )
        .trim();
    if (v.isEmpty) return null;
    switch (kind) {
      case OptionKind.choice:
        final c = v.toLowerCase();
        return choices.contains(c) ? c : null;
      case OptionKind.text:
        return v.runes.length > 40 ? String.fromCharCodes(v.runes.take(40)) : v;
      case OptionKind.integer:
        final n = double.tryParse(v);
        return n?.round().clamp(min, max).toString();
      case OptionKind.flag:
        final f = v.toLowerCase();
        if (const {'1', 'true', 'yes', 'on'}.contains(f)) return '1';
        if (const {'0', 'false', 'no', 'off'}.contains(f)) return '0';
        return null;
      case OptionKind.date:
        return isValidDbDate(v) ? v : null;
      case OptionKind.time:
        return RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v) ? v : null;
      case OptionKind.dateList:
        final dates = [
          for (final p in v.split(RegExp(r'[,\s;]+')))
            if (isValidDbDate(p)) p,
        ].take(62).toList();
        return dates.isEmpty ? null : dates.join(',');
      case OptionKind.month:
        final m = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$').hasMatch(v);
        return m ? v : null;
      case OptionKind.timezone:
        return WidgetLibrary.normalizeTimezone(v);
      case OptionKind.itemList:
        // One task per line or separated by "|". List markers the AI may add are removed.
        final tasks = [
          for (final t in v.split(RegExp(r'[|\n]')))
            () {
              final c = t.replaceFirst(RegExp(r'^\s*(?:[-*•]|\[[ xX]?\]|\d+[.)])\s+'), '').trim();
              return c.runes.length > 60 ? String.fromCharCodes(c.runes.take(60)) : c;
            }(),
        ].where((t) => t.isNotEmpty).take(30).toList();
        return tasks.isEmpty ? null : tasks.join('|');
      case OptionKind.indexList:
        final nums = {
          for (final p in v.split(RegExp(r'[,\s;]+')))
            if (int.tryParse(p) case final n? when n >= 1 && n <= 30) n,
        }.toList()..sort();
        return nums.isEmpty ? null : nums.join(',');
    }
  }
}

const widgetThemes = ['auto', 'dark', 'terracotta', 'sage', 'periwinkle', 'navy', 'teal', 'rose'];
const _theme = WidgetOption(
  'theme',
  'Color',
  OptionKind.choice,
  choices: widgetThemes,
  defaultValue: 'auto',
);
const _label = WidgetOption('label', 'Label', OptionKind.text);

class LibraryWidget {
  final String kind;
  final String label;
  final String description;
  final String icon;
  final List<WidgetOption> options;
  const LibraryWidget(this.kind, this.label, this.description, this.icon, this.options);

  String get path => '$widgetsBaseUrl/$kind.html';

  WidgetOption? option(String name) {
    for (final o in options) {
      if (o.name == name) return o;
    }
    return null;
  }
}

/// The result of building a widget link.
class WidgetBuild {
  /// Null when a required setting is missing or invalid.
  final String? url;

  /// Problems by option name. Optional options that were invalid are left out of
  /// the link and reported here; required ones also make [url] null.
  final Map<String, String> errors;
  const WidgetBuild(this.url, this.errors);
}

class WidgetLibrary {
  static const all = <LibraryWidget>[
    LibraryWidget('clock', 'Clock', 'A live clock for any time zone, digital or analog.', '🕒', [
      WidgetOption('tz', 'Time zone', OptionKind.timezone),
      WidgetOption(
        'style',
        'Style',
        OptionKind.choice,
        choices: ['digital', 'analog'],
        defaultValue: 'digital',
      ),
      WidgetOption('hour12', '12-hour time', OptionKind.flag, defaultValue: '0'),
      WidgetOption('seconds', 'Show seconds', OptionKind.flag, defaultValue: '1'),
      WidgetOption('date', 'Show date', OptionKind.flag, defaultValue: '1'),
      _label,
      _theme,
    ]),
    LibraryWidget(
      'timer',
      'Timer',
      'A Pomodoro focus timer, a countdown timer, or a stopwatch.',
      '⏱️',
      [
        WidgetOption(
          'mode',
          'Mode',
          OptionKind.choice,
          choices: ['pomodoro', 'countdown', 'stopwatch'],
          defaultValue: 'pomodoro',
        ),
        WidgetOption(
          'focus',
          'Focus minutes',
          OptionKind.integer,
          min: 1,
          max: 180,
          defaultValue: '25',
        ),
        WidgetOption(
          'break',
          'Break minutes',
          OptionKind.integer,
          min: 1,
          max: 60,
          defaultValue: '5',
        ),
        WidgetOption(
          'long',
          'Long break minutes',
          OptionKind.integer,
          min: 1,
          max: 120,
          defaultValue: '15',
        ),
        WidgetOption('rounds', 'Rounds', OptionKind.integer, min: 1, max: 12, defaultValue: '4'),
        WidgetOption(
          'minutes',
          'Countdown minutes',
          OptionKind.integer,
          min: 1,
          max: 600,
          defaultValue: '10',
        ),
        WidgetOption('auto', 'Start next round automatically', OptionKind.flag, defaultValue: '0'),
        _theme,
      ],
    ),
    LibraryWidget(
      'countdown',
      'Countdown',
      'Days, hours and minutes until a date, such as an exam or trip.',
      '⏳',
      [
        WidgetOption('date', 'Date', OptionKind.date, required: true),
        WidgetOption('time', 'Time', OptionKind.time),
        _label,
        _theme,
      ],
    ),
    LibraryWidget(
      'calendar',
      'Calendar',
      'A month calendar that highlights today and any dates you mark.',
      '📅',
      [
        WidgetOption(
          'start',
          'Week starts on',
          OptionKind.choice,
          choices: ['mon', 'sun'],
          defaultValue: 'mon',
        ),
        WidgetOption('mark', 'Marked dates', OptionKind.dateList),
        WidgetOption('month', 'Starting month', OptionKind.month),
        _theme,
      ],
    ),
    LibraryWidget(
      'checklist',
      'Checklist',
      'Tasks you can tick inside the widget, with a progress bar that follows them (ticks are saved per device, not synced).',
      '✅',
      [
        WidgetOption('items', 'Tasks', OptionKind.itemList, required: true),
        WidgetOption('title', 'Title', OptionKind.text),
        WidgetOption('done', 'Already done (task numbers)', OptionKind.indexList),
        _theme,
      ],
    ),
    LibraryWidget(
      'progress',
      'Time progress bar',
      'How far through the day, week, month, year or a date range you are (time only, not tasks).',
      '📊',
      [
        WidgetOption(
          'type',
          'Period',
          OptionKind.choice,
          choices: ['day', 'week', 'month', 'year', 'custom'],
          defaultValue: 'year',
        ),
        WidgetOption('start', 'Start date (custom)', OptionKind.date),
        WidgetOption('end', 'End date (custom)', OptionKind.date),
        _label,
        _theme,
      ],
    ),
    LibraryWidget('quote', 'Quote', 'A short motivating line that changes every day.', '💬', [
      WidgetOption(
        'tag',
        'Topic',
        OptionKind.choice,
        choices: ['any', 'study', 'focus', 'calm'],
        defaultValue: 'any',
      ),
      _theme,
    ]),
  ];

  static LibraryWidget? byKind(String kind) {
    final k = kind.trim().toLowerCase();
    for (final w in all) {
      if (w.kind == k) return w;
    }
    return null;
  }

  /// Builds the link for [kind] from loosely typed [options]. Returns null if
  /// [kind] isn't a library widget.
  static WidgetBuild? build(String kind, Map<String, String> options) {
    final w = byKind(kind);
    if (w == null) return null;
    final params = <String, String>{};
    final errors = <String, String>{};
    for (final o in w.options) {
      final raw = options[o.name];
      if (raw == null || raw.trim().isEmpty) {
        if (o.required) errors[o.name] = '${o.label} is required';
        continue;
      }
      final v = o.normalize(raw);
      if (v == null) {
        errors[o.name] = '"${raw.trim()}" is not a valid ${o.label.toLowerCase()}';
      } else {
        params[o.name] = v;
      }
    }
    // A custom progress bar needs both dates, in order.
    final custom = w.kind == 'progress' && params['type'] == 'custom';
    if (custom) {
      for (final n in const ['start', 'end']) {
        if (!params.containsKey(n)) {
          errors.putIfAbsent(n, () => 'A custom progress bar needs a $n date');
        }
      }
      final s = params['start'], e = params['end'];
      if (s != null && e != null && e.compareTo(s) <= 0) {
        errors['end'] = 'The end date must be after the start date';
      }
    }
    // Missing or invalid optional settings are simply left out of the link;
    // required ones (and a custom range) make the widget unusable.
    final blocked = errors.keys.any(
      (n) => (w.option(n)?.required ?? false) || (custom && (n == 'start' || n == 'end')),
    );
    if (blocked) return WidgetBuild(null, errors);
    final uri = Uri.parse(w.path).replace(queryParameters: params.isEmpty ? null : params);
    return WidgetBuild(uri.toString(), errors);
  }

  /// Recognises a link made by [build]: its widget and settings, or null.
  static ({LibraryWidget widget, Map<String, String> options})? parse(String url) {
    final u = Uri.tryParse(url.trim());
    final base = Uri.parse(widgetsBaseUrl);
    if (u == null || u.scheme != 'https' || u.host != base.host) return null;
    for (final w in all) {
      if (u.path == Uri.parse(w.path).path) return (widget: w, options: Map.of(u.queryParameters));
    }
    return null;
  }

  /// A friendly name for a link, for example "Clock · Asia/Kolkata", or null.
  static String? describe(String url) {
    final p = parse(url);
    if (p == null) return null;
    final o = p.options;
    final detail = switch (p.widget.kind) {
      'clock' => o['label'] ?? o['tz'],
      'timer' =>
        o['mode'] == 'countdown'
            ? '${o['minutes'] ?? 10} min countdown'
            : o['mode'] == 'stopwatch'
            ? 'stopwatch'
            : '${o['focus'] ?? 25}/${o['break'] ?? 5} min Pomodoro',
      'countdown' => o['label'] ?? o['date'],
      'progress' => o['label'] ?? o['type'],
      'checklist' =>
        o['title'] ?? '${(o['items'] ?? '').split('|').where((t) => t.isNotEmpty).length} tasks',
      'quote' => o['tag'],
      _ => null,
    };
    return detail == null || detail.isEmpty ? p.widget.label : '${p.widget.label} · $detail';
  }

  /// The section of the AI prompt that describes the library.
  static String promptSection() => [
    for (final w in all)
      '- ${w.kind}: ${w.description} Options: ${w.options.map((o) => o.promptHint).join(', ')}.',
  ].join('\n');

  // ---- time zones -----------------------------------------------------------

  /// Common names and aliases -> IANA zone names.
  static const _zoneAliases = <String, String>{
    'india': 'Asia/Kolkata',
    'ist': 'Asia/Kolkata',
    'kolkata': 'Asia/Kolkata',
    'delhi': 'Asia/Kolkata',
    'mumbai': 'Asia/Kolkata',
    'london': 'Europe/London',
    'uk': 'Europe/London',
    'gmt': 'Europe/London',
    'britain': 'Europe/London',
    'paris': 'Europe/Paris',
    'france': 'Europe/Paris',
    'berlin': 'Europe/Berlin',
    'germany': 'Europe/Berlin',
    'madrid': 'Europe/Madrid',
    'spain': 'Europe/Madrid',
    'rome': 'Europe/Rome',
    'italy': 'Europe/Rome',
    'amsterdam': 'Europe/Amsterdam',
    'zurich': 'Europe/Zurich',
    'istanbul': 'Europe/Istanbul',
    'moscow': 'Europe/Moscow',
    'new york': 'America/New_York',
    'nyc': 'America/New_York',
    'est': 'America/New_York',
    'eastern': 'America/New_York',
    'chicago': 'America/Chicago',
    'cst': 'America/Chicago',
    'central': 'America/Chicago',
    'denver': 'America/Denver',
    'mst': 'America/Denver',
    'mountain': 'America/Denver',
    'los angeles': 'America/Los_Angeles',
    'la': 'America/Los_Angeles',
    'california': 'America/Los_Angeles',
    'pst': 'America/Los_Angeles',
    'pacific': 'America/Los_Angeles',
    'toronto': 'America/Toronto',
    'vancouver': 'America/Vancouver',
    'mexico city': 'America/Mexico_City',
    'sao paulo': 'America/Sao_Paulo',
    'são paulo': 'America/Sao_Paulo',
    'brazil': 'America/Sao_Paulo',
    'tokyo': 'Asia/Tokyo',
    'japan': 'Asia/Tokyo',
    'seoul': 'Asia/Seoul',
    'korea': 'Asia/Seoul',
    'shanghai': 'Asia/Shanghai',
    'beijing': 'Asia/Shanghai',
    'china': 'Asia/Shanghai',
    'hong kong': 'Asia/Hong_Kong',
    'singapore': 'Asia/Singapore',
    'dubai': 'Asia/Dubai',
    'uae': 'Asia/Dubai',
    'karachi': 'Asia/Karachi',
    'pakistan': 'Asia/Karachi',
    'dhaka': 'Asia/Dhaka',
    'bangkok': 'Asia/Bangkok',
    'jakarta': 'Asia/Jakarta',
    'manila': 'Asia/Manila',
    'sydney': 'Australia/Sydney',
    'melbourne': 'Australia/Melbourne',
    'australia': 'Australia/Sydney',
    'auckland': 'Pacific/Auckland',
    'new zealand': 'Pacific/Auckland',
    'cairo': 'Africa/Cairo',
    'lagos': 'Africa/Lagos',
    'nairobi': 'Africa/Nairobi',
    'johannesburg': 'Africa/Johannesburg',
    'south africa': 'Africa/Johannesburg',
    'utc': 'UTC',
  };

  static final _ianaByLower = {for (final z in _zoneAliases.values) z.toLowerCase(): z};

  /// An IANA zone name for [raw] (a zone name or a common city/country name), or null.
  static String? normalizeTimezone(String raw) {
    final v = raw.trim().toLowerCase().replaceAll(RegExp(r'\s*(time|standard time|zone)$'), '');
    final direct = _ianaByLower[v.replaceAll(' ', '_')];
    return direct ?? _zoneAliases[v];
  }

  /// A few examples for the AI prompt.
  static const exampleZones =
      'Asia/Kolkata, Europe/London, America/New_York, America/Los_Angeles, Asia/Tokyo, Australia/Sydney';
}
