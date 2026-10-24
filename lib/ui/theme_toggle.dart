import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../storage.dart';
import '../theme.dart';
import 'motion.dart';
import 'pressable.dart';

/// Cycles System -> Light -> Dark with a rotating sun / moon icon.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key, required this.store});

  final SectionStore store;

  static String _name(ThemeMode m) => switch (m) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mode = store.themeMode;
    final next = ThemeMode.values[(mode.index + 1) % ThemeMode.values.length];
    final icon = switch (mode) {
      ThemeMode.system => LucideIcons.sunMoon,
      ThemeMode.light => LucideIcons.sun,
      ThemeMode.dark => LucideIcons.moon,
    };
    final label = 'Theme: ${_name(mode)}. Switch to ${_name(next)}';
    return Tooltip(
      message: label,
      child: Pressable(
        onTap: store.cycleTheme,
        semanticLabel: label,
        borderRadius: BorderRadius.circular(999),
        hoverLift: 0,
        pressedScale: 0.9,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.glass,
            border: Border.all(color: c.glassBorder),
          ),
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.slow),
            switchInCurve: Motion.spring,
            transitionBuilder: (child, a) => RotationTransition(
              turns: Tween<double>(begin: -0.35, end: 0).animate(a),
              child: ScaleTransition(scale: a, child: child),
            ),
            child: Icon(icon, key: ValueKey(mode), size: 21, color: c.text),
          ),
        ),
      ),
    );
  }
}
