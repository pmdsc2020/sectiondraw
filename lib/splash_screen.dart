import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'storage.dart';
import 'theme.dart';
import 'ui/glass.dart';
import 'ui/logo.dart';
import 'ui/motion.dart';

/// Opening animation: the logo draws its cross-section, the wordmark rises
/// in letter by letter, then the app cross-fades to the home screen.
/// Tap anywhere to skip.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.store});

  final SectionStore store;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _word = 'SectionDraw';

  late final AnimationController _text = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));
  bool _left = false;

  void _logoDone() {
    if (!mounted) return;
    if (Motion.reduced(context)) {
      _text.value = 1;
      Future<void>.delayed(const Duration(milliseconds: 350), _go);
      return;
    }
    _text.forward().whenComplete(
        () => Future<void>.delayed(const Duration(milliseconds: 450), _go));
  }

  void _go() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: Motion.of(context, const Duration(milliseconds: 650)),
      pageBuilder: (_, __, ___) => HomeScreen(store: widget.store),
      transitionsBuilder: (_, a, __, child) {
        final t = CurvedAnimation(parent: a, curve: Motion.emphasized);
        return FadeTransition(
          opacity: t,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.04, end: 1).animate(t),
            child: child,
          ),
        );
      },
    ));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: AuroraBackground(
        child: Semantics(
          button: true,
          label: 'SectionDraw. Tap to skip intro',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _go,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedLogo(size: 128, pulse: true, onDone: _logoDone),
                  const SizedBox(height: 30),
                  AnimatedBuilder(
                    animation: _text,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _word.length; i++) _letter(i, c),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  FadeTransition(
                    opacity: CurvedAnimation(
                        parent: _text, curve: const Interval(0.5, 1)),
                    child: Text(
                      'GPS CROSS-SECTION SURVEY',
                      style: eyebrow(c.muted).copyWith(letterSpacing: 3),
                    ),
                  ),
                  const SizedBox(height: 34),
                  SizedBox(
                    width: 120,
                    child: AnimatedBuilder(
                      animation: _text,
                      builder: (context, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: _text.value,
                          minHeight: 3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _letter(int i, AppColors c) {
    final start = i / _word.length * 0.6;
    final t = Curves.easeOutBack
        .transform(((_text.value - start) / 0.4).clamp(0.0, 1.0).toDouble());
    // "Section" in text colour, "Draw" in brand colour.
    final color = i < 7 ? c.text : context.scheme.primary;
    return Opacity(
      opacity: t.clamp(0.0, 1.0).toDouble(),
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 18),
        child:
            Text(_word[i], style: display(38, color: color, letterSpacing: -1)),
      ),
    );
  }
}
