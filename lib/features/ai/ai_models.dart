/// Open-source models offered in the app. All run locally through Ollama.
class RecommendedModel {
  final String tag;
  final String label;
  final String note;
  final String size;
  final bool vision;
  const RecommendedModel(this.tag, this.label, this.note, this.size, {this.vision = false});

  static const all = [
    RecommendedModel(
      'qwen3.5:9b',
      'Qwen 3.5 · 9B',
      'Recommended. Best quality, reads images such as timetable screenshots. Needs about 8 GB of free memory.',
      '6.6 GB',
      vision: true,
    ),
    RecommendedModel(
      'qwen3.5:4b',
      'Qwen 3.5 · 4B',
      'Lighter and faster, for Macs and PCs with 8 GB of memory. Also reads images.',
      '3.3 GB',
      vision: true,
    ),
    RecommendedModel(
      'qwen2.5:7b',
      'Qwen 2.5 · 7B',
      'Text only, a proven all-rounder that works with older versions of Ollama.',
      '4.7 GB',
    ),
  ];

  static RecommendedModel? byTag(String tag) {
    for (final m in all) {
      if (m.tag == tag) return m;
    }
    return null;
  }
}
