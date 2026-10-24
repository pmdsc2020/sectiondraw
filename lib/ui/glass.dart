import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'motion.dart';
import 'pressable.dart';

/// Frosted-glass surface. Set [blur] false for surfaces repeated in long
/// lists: the translucent fill still reads as glass and scrolls cheaply on
/// low-end field phones.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.blur = true,
    this.strong = false,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;
  final bool strong;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  /// Optional colour washed over the glass (e.g. status colour).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final br = BorderRadius.circular(radius);
    final fill = strong ? c.glassStrong : c.glass;
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tint == null ? fill : Color.alphaBlend(tint!.withAlpha(40), fill),
            fill.withAlpha((fill.a * 255 * 0.82).round()),
          ],
        ),
        border: Border.all(color: c.glassBorder),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (blur) {
      body = ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: body,
        ),
      );
    }
    if (onTap == null && onLongPress == null) {
      return Semantics(container: true, label: semanticLabel, child: body);
    }
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: semanticLabel,
      borderRadius: br,
      child: body,
    );
  }
}

/// Slowly drifting colour blobs behind the app: gives the glass something
/// to frost. Freezes when the OS asks for reduced motion.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.bgTop, c.bgBottom],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _AuroraPainter(
                      t: _c.value, colors: [c.blobA, c.blobB, c.blobC]),
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.t, required this.colors});

  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * 2 * math.pi;
    final r = size.shortestSide;
    final blobs = <(Offset, double, Color)>[
      (
        Offset(size.width * (0.15 + 0.10 * math.sin(a)),
            size.height * (0.12 + 0.05 * math.cos(a))),
        r * 0.75,
        colors[0],
      ),
      (
        Offset(size.width * (0.95 + 0.08 * math.cos(a + 1.7)),
            size.height * (0.38 + 0.08 * math.sin(a + 1.7))),
        r * 0.65,
        colors[1],
      ),
      (
        Offset(size.width * (0.30 + 0.12 * math.sin(a + 3.4)),
            size.height * (0.92 + 0.04 * math.cos(a + 3.4))),
        r * 0.7,
        colors[2],
      ),
    ];
    for (final (center, radius, color) in blobs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withAlpha(0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) =>
      old.t != t || old.colors != colors;
}
