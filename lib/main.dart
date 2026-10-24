import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'splash_screen.dart';
import 'storage.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SectionStore();
  await store.load();
  runApp(SectionDrawApp(store: store));
}

class SectionDrawApp extends StatelessWidget {
  const SectionDrawApp({super.key, required this.store, this.splash = true});

  final SectionStore store;

  /// Play the opening logo animation before the home screen.
  final bool splash;

  static final ThemeData _light = buildTheme(Brightness.light);
  static final ThemeData _dark = buildTheme(Brightness.dark);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: 'SectionDraw',
        debugShowCheckedModeBanner: false,
        theme: _light,
        darkTheme: _dark,
        themeMode: store.themeMode,
        themeAnimationDuration: const Duration(milliseconds: 400),
        themeAnimationCurve: Curves.easeOutCubic,
        home: splash ? SplashScreen(store: store) : HomeScreen(store: store),
      ),
    );
  }
}
