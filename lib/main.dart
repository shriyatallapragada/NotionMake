import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_theme.dart';
import 'theme_mode.dart';
import 'features/editor/providers/providers.dart';
import 'features/editor/screens/builder_screen.dart';
import 'features/onboarding/connect_screen.dart';

void main() => runApp(const ProviderScope(child: NotionMakeApp()));

class NotionMakeApp extends ConsumerWidget {
  const NotionMakeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'NotionMake',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      home: const _Root(),
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.watch(tokenProvider);
    return token.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const ConnectScreen(),
      data: (t) => t == null ? const ConnectScreen() : const BuilderScreen(),
    );
  }
}
