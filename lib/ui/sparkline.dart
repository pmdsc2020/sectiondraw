import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Tiny preview of a section profile for list cards.
class ProfileSparkline extends StatelessWidget {
  const ProfileSparkline({super.key, required this.profile, this.size = 64});

  final List<ProfilePoint> profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              c.brandGradient.first.withAlpha(46),
              c.brandGradient.last.withAlpha(30),
            ],
          ),
          border: Border.all(color: c.glassBorder),
        ),
        child: CustomPaint(
          painter: _SparkPainter(
            profile: profile,
            line: context.scheme.primary,
            water: c.water,
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(
      {required this.profile, required this.line, required this.water});

  final List<ProfilePoint> profile;
  final Color line;
  final Color water;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = size.shortestSide * 0.18;
    final area =
        Rect.fromLTWH(pad, pad, size.width - 2 * pad, size.height - 2 * pad);
    final paint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (profile.length < 2) {
      // Placeholder: a dashed baseline with one dot per captured point.
      final y = area.center.dy;
      for (var x = area.left; x < area.right; x += 7) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 3.5, area.right), y),
            paint..color = line.withAlpha(120));
      }
      if (profile.length == 1) {
        canvas.drawCircle(Offset(area.left, y), 3.5, Paint()..color = line);
      }
      return;
    }

    var lo = profile.first.elevation, hi = lo;
    for (final p in profile) {
      lo = math.min(lo, p.elevation);
      hi = math.max(hi, p.elevation);
    }
    final d0 = profile.first.distance;
    final dw = math.max(profile.last.distance - d0, 1e-6);
    final eh = math.max(hi - lo, 1e-6);
    Offset at(ProfilePoint p) => Offset(
          area.left + (p.distance - d0) / dw * area.width,
          area.top + (hi - p.elevation) / eh * area.height,
        );

    final path = Path()..moveTo(at(profile.first).dx, at(profile.first).dy);
    for (final p in profile.skip(1)) {
      final o = at(p);
      path.lineTo(o.dx, o.dy);
    }
    final fill = Path.from(path)
      ..lineTo(area.right, size.height)
      ..lineTo(area.left, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withAlpha(70), line.withAlpha(0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(path, paint);

    var low = profile.first;
    for (final p in profile) {
      if (p.elevation < low.elevation) low = p;
    }
    canvas.drawCircle(at(low), 3.6, Paint()..color = water);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.profile != profile || old.line != line || old.water != water;
}
