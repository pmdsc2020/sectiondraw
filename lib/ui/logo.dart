import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'motion.dart';

/// Normalised cross-section used by the logo: left bank -> bed -> right bank.
const List<Offset> _profile = [
  Offset(0.12, 0.40),
  Offset(0.27, 0.45),
  Offset(0.38, 0.64),
  Offset(0.50, 0.74),
  Offset(0.62, 0.63),
  Offset(0.74, 0.47),
  Offset(0.88, 0.41),
];

double _seg(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();

/// Paints the SectionDraw mark at animation time [t] (0..1):
/// the ground line draws itself, survey points pop in, water rises in the
/// channel, then a GPS pin drops onto the bed. [ping] (0..1) draws an
/// expanding "signal" ring around the pin.
class LogoPainter extends CustomPainter {
  LogoPainter({required this.t, this.ping = 0, required this.gradient});

  final double t;
  final double ping;
  final List<Color> gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Offset.zero & Size(s, s);
    final r = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.28));

    // Tile.
    canvas.drawRRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ).createShader(rect),
    );
    // Top highlight for depth.
    canvas.drawRRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [Colors.white.withAlpha(60), Colors.white.withAlpha(0)],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipRRect(r);

    final pts = [for (final p in _profile) Offset(p.dx * s, p.dy * s)];
    // The banks continue to the tile edges; dots mark only surveyed points.
    final ground = Path()..moveTo(0, pts.first.dy - s * 0.02);
    for (final p in pts) {
      ground.lineTo(p.dx, p.dy);
    }
    ground.lineTo(s, pts.last.dy - s * 0.02);

    // Water: above ground, below the rising level.
    final tw = Curves.easeOutCubic.transform(_seg(t, 0.50, 0.85));
    if (tw > 0) {
      final bed = pts[3].dy;
      final level = bed - (bed - 0.53 * s) * tw;
      final above = Path.from(ground)
        ..lineTo(s, 0)
        ..lineTo(0, 0)
        ..close();
      canvas.save();
      canvas.clipPath(above);
      canvas.drawRect(
        Rect.fromLTRB(0, level, s, s),
        Paint()..color = const Color(0xFFBAE6FD).withAlpha((200 * tw).round()),
      );
      canvas.drawLine(
        Offset(0, level),
        Offset(s, level),
        Paint()
          ..color = Colors.white.withAlpha((230 * tw).round())
          ..strokeWidth = s * 0.018,
      );
      canvas.restore();
    }

    // Ground fill under the line.
    final tf = _seg(t, 0.35, 0.7);
    if (tf > 0) {
      final under = Path.from(ground)
        ..lineTo(s, s)
        ..lineTo(0, s)
        ..close();
      canvas.drawPath(
          under, Paint()..color = Colors.white.withAlpha((52 * tf).round()));
    }

    // Ground line, drawn progressively.
    final tl = Curves.easeInOutCubic.transform(_seg(t, 0.08, 0.6));
    if (tl > 0) {
      final metric = ground.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * tl),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.055
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Survey points pop in one after another.
    for (var i = 0; i < pts.length; i++) {
      final start = 0.18 + i * 0.06;
      final tp = Curves.easeOutBack.transform(_seg(t, start, start + 0.16));
      if (tp <= 0) continue;
      final bed = i == 3;
      canvas.drawCircle(
          pts[i], s * (bed ? 0.05 : 0.04) * tp, Paint()..color = Colors.white);
      canvas.drawCircle(
        pts[i],
        s * (bed ? 0.025 : 0.018) * tp,
        Paint()..color = bed ? const Color(0xFF0369A1) : gradient.first,
      );
    }
    canvas.restore();

    // GPS pin drops in and hovers above the bed, pointing at it.
    final tpin = _seg(t, 0.68, 1.0);
    if (tpin > 0) {
      final drop = Curves.bounceOut.transform(tpin);
      final tip = Offset(pts[3].dx, s * 0.33);
      final y = tip.dy - (1 - drop) * s * 0.4;
      final head = Offset(tip.dx, y - s * 0.15);
      final hr = s * 0.085;

      if (ping > 0 && tpin >= 1) {
        canvas.drawCircle(
          head,
          hr + s * 0.22 * ping,
          Paint()
            ..color = Colors.white.withAlpha((150 * (1 - ping)).round())
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.02,
        );
      }

      final pin = Path()
        ..moveTo(tip.dx, y)
        ..quadraticBezierTo(
            head.dx - hr * 1.15, head.dy + hr * 0.75, head.dx - hr, head.dy)
        ..arcTo(
            Rect.fromCircle(center: head, radius: hr), math.pi, math.pi, false)
        ..quadraticBezierTo(head.dx + hr * 1.15, head.dy + hr * 0.75, tip.dx, y)
        ..close();
      canvas.drawShadow(pin, Colors.black, s * 0.02, false);
      canvas.drawPath(pin, Paint()..color = Colors.white);
      canvas.drawCircle(head, hr * 0.42, Paint()..color = gradient.last);
    }
  }

  @override
  bool shouldRepaint(covariant LogoPainter old) =>
      old.t != t || old.ping != ping || old.gradient != gradient;
}

/// The SectionDraw logo. With [animate] it plays the intro motion once,
/// and with [pulse] keeps a soft GPS "ping" going afterwards.
class AnimatedLogo extends StatefulWidget {
  const AnimatedLogo({
    super.key,
    this.size = 120,
    this.animate = true,
    this.pulse = false,
    this.duration = const Duration(milliseconds: 1700),
    this.onDone,
  });

  final double size;
  final bool animate;
  final bool pulse;
  final Duration duration;
  final VoidCallback? onDone;

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: widget.duration);
  late final AnimationController _ping = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.animate || Motion.reduced(context)) {
      _intro.value = 1;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onDone?.call());
      return;
    }
    _intro.forward().whenComplete(() {
      if (!mounted) return;
      widget.onDone?.call();
      if (widget.pulse) _ping.repeat();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _ping.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = context.colors.brandGradient;
    return Semantics(
      label: 'SectionDraw logo',
      image: true,
      child: AnimatedBuilder(
        animation: Listenable.merge([_intro, _ping]),
        builder: (context, _) {
          final t = _intro.value;
          // Tile springs in during the first 30 %.
          final scale = Curves.easeOutBack.transform(_seg(t, 0, 0.3));
          final rot =
              (1 - Curves.easeOutCubic.transform(_seg(t, 0, 0.35))) * -0.35;
          return Transform.rotate(
            angle: rot,
            child: Transform.scale(
              scale: 0.4 + 0.6 * scale,
              child: Opacity(
                opacity: _seg(t, 0, 0.12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.size * 0.28),
                    boxShadow: [
                      BoxShadow(
                        color: g.last.withAlpha((110 * t).round()),
                        blurRadius: widget.size * 0.35,
                        offset: Offset(0, widget.size * 0.1),
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    size: Size.square(widget.size),
                    painter: LogoPainter(t: t, ping: _ping.value, gradient: g),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Static logo for headers.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: LogoPainter(t: 1, gradient: context.colors.brandGradient),
      ),
    );
  }
}
