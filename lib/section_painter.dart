import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

/// What to write above each point on the graph.
enum PointLabel { elevation, note, none }

class ChartStyle {
  const ChartStyle({
    required this.background,
    required this.text,
    required this.subtext,
    required this.grid,
    required this.axis,
    required this.ground,
    required this.groundFill,
    required this.lowPoint,
    required this.scale,
  });

  final Color background;
  final Color text;
  final Color subtext;
  final Color grid;
  final Color axis;
  final Color ground;
  final Color groundFill;
  final Color lowPoint;

  /// Multiplies all font sizes, line widths and margins.
  final double scale;

  static const ChartStyle screen = ChartStyle(
    background: Color(0xFFFFFFFF),
    text: Color(0xFF212121),
    subtext: Color(0xFF616161),
    grid: Color(0xFFE3E3E3),
    axis: Color(0xFF424242),
    ground: Color(0xFF5D4037),
    groundFill: Color(0x66BCAAA4),
    lowPoint: Color(0xFF1565C0),
    scale: 1.0,
  );

  static const ChartStyle export = ChartStyle(
    background: Color(0xFFFFFFFF),
    text: Color(0xFF111111),
    subtext: Color(0xFF555555),
    grid: Color(0xFFDDDDDD),
    axis: Color(0xFF333333),
    ground: Color(0xFF5D4037),
    groundFill: Color(0x66BCAAA4),
    lowPoint: Color(0xFF1565C0),
    scale: 2.0,
  );
}

/// Draws a 2D cross-section: X = distance (m), Y = elevation (m).
class SectionPainter extends CustomPainter {
  SectionPainter({
    required this.profile,
    required this.style,
    this.label = PointLabel.elevation,
    this.dataBands = false,
  });

  final List<ProfilePoint> profile;
  final ChartStyle style;
  final PointLabel label;

  /// Draw "Distance" and "RL" rows under the graph (engineering drawing style).
  final bool dataBands;

  static TextPainter textPainter(String s, double size, Color c,
      {FontWeight weight = FontWeight.normal, Color? halo}) {
    return TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: c,
          fontSize: size,
          fontWeight: weight,
          backgroundColor: halo,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  /// Paint [tp] at [at]; (ax, ay) = anchor fraction of text box; [angle] rad.
  static void drawText(Canvas canvas, TextPainter tp, Offset at,
      {double ax = 0, double ay = 0, double angle = 0}) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (angle != 0) canvas.rotate(angle);
    tp.paint(canvas, Offset(-tp.width * ax, -tp.height * ay));
    canvas.restore();
  }

  static int _decimals(double step) {
    if ((step - step.roundToDouble()).abs() < 1e-9) return 0;
    final s10 = step * 10;
    if ((s10 - s10.roundToDouble()).abs() < 1e-9) return 1;
    return 2;
  }

  /// Choose which labels to draw so they do not overlap.
  static List<bool> _pick(
      List<double> xs, List<bool> has, Set<int> forced, double need) {
    final out = List<bool>.filled(xs.length, false);
    var lastX = -1e12;
    for (var i = 0; i < xs.length; i++) {
      if (!has[i]) continue;
      final x = xs[i];
      if (forced.contains(i)) {
        out[i] = true;
        lastX = x;
        continue;
      }
      if (x - lastX < need) continue;
      var clash = false;
      for (final j in forced) {
        if (j != i && has[j] && (xs[j] - x).abs() < need) {
          clash = true;
          break;
        }
      }
      if (clash) continue;
      out[i] = true;
      lastX = x;
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final f = style.scale;
    canvas.drawRect(Offset.zero & size, Paint()..color = style.background);

    if (profile.length < 2) {
      drawText(
        canvas,
        textPainter('Capture at least 2 points to draw the section',
            14 * f, style.subtext),
        Offset(size.width / 2, size.height / 2),
        ax: 0.5,
        ay: 0.5,
      );
      return;
    }

    // ---------- data ranges ----------
    var dMin = profile.first.distance;
    var dMax = profile.first.distance;
    var eMin = profile.first.elevation;
    var eMax = profile.first.elevation;
    var lowIdx = 0;
    for (var i = 0; i < profile.length; i++) {
      final p = profile[i];
      dMin = math.min(dMin, p.distance);
      dMax = math.max(dMax, p.distance);
      eMax = math.max(eMax, p.elevation);
      if (p.elevation < eMin) {
        eMin = p.elevation;
        lowIdx = i;
      }
    }
    var eRange = eMax - eMin;
    if (eRange < 0.5) {
      final mid = (eMax + eMin) / 2;
      eMin = mid - 0.25;
      eMax = mid + 0.25;
      eRange = 0.5;
    }
    final yStep = niceStep(eRange / 5);
    final headroom = label == PointLabel.none ? 0.08 : 0.30;
    final yLo = ((eMin - eRange * 0.08) / yStep).floor() * yStep;
    final yHi = ((eMax + eRange * headroom) / yStep).ceil() * yStep;

    final x0 = math.min(0.0, dMin);
    var xSpan = dMax - x0;
    if (xSpan < 1) xSpan = 1;
    final xStep = niceStep(xSpan / 6);
    final xLo = (x0 / xStep).floor() * xStep;
    // Right edge = last point (no empty space after it).
    var xHi = x0 + xSpan;
    if (xHi - xLo < xStep * 0.5) xHi = xLo + xStep * 0.5;

    // ---------- text sizes & margins ----------
    final tickSize = 11 * f;
    final titleSize = 12 * f;
    final labelSize = 11 * f;
    final yDec = _decimals(yStep);
    final xDec = _decimals(xStep);

    final yTicks = <double>[];
    final ny = ((yHi - yLo) / yStep).round();
    for (var i = 0; i <= ny; i++) {
      yTicks.add(yLo + i * yStep);
    }
    final xTicks = <double>[];
    for (var i = 0; xLo + i * xStep <= xHi + xStep * 1e-6; i++) {
      xTicks.add(xLo + i * xStep);
    }

    var yTickW = 0.0;
    for (final y in yTicks) {
      yTickW = math.max(
          yTickW, textPainter(y.toStringAsFixed(yDec), tickSize, style.text).width);
    }
    final tickH = textPainter('0', tickSize, style.text).height;
    final titleH = textPainter('Ag', titleSize, style.text).height;
    final labelH = textPainter('0', labelSize, style.text).height;

    // Data band rows (export).
    final distStr = [for (final p in profile) p.distance.toStringAsFixed(2)];
    final elevStr = [for (final p in profile) p.elevation.toStringAsFixed(2)];
    var bandRowH = 0.0;
    var bandHeadW = 0.0;
    if (dataBands) {
      var w = 0.0;
      for (final s in [...distStr, ...elevStr]) {
        w = math.max(w, textPainter(s, labelSize, style.text).width);
      }
      bandRowH = w + 14 * f;
      bandHeadW = math.max(
        textPainter('Dist. (m)', labelSize, style.text, weight: FontWeight.bold)
            .width,
        textPainter('RL (m)', labelSize, style.text, weight: FontWeight.bold)
            .width,
      );
    }

    var left = 6 * f + titleH + 6 * f + yTickW + 6 * f;
    if (dataBands) left = math.max(left, bandHeadW + 18 * f);
    final right = 16 * f;
    final top = 10 * f;
    final axisBlock = 4 * f + tickH + 6 * f + titleH + 8 * f;
    final bottom = axisBlock + (dataBands ? 2 * bandRowH + 4 * f : 0);
    final plot = Rect.fromLTRB(
        left, top, size.width - right, size.height - bottom);
    if (plot.width < 20 || plot.height < 20) return;

    // Keep first/last points (and their labels) off the frame lines.
    final inset = labelH * 0.7 + 4 * f;
    double px(double x) =>
        plot.left + inset + (x - xLo) / (xHi - xLo) * (plot.width - 2 * inset);
    double py(double y) => plot.bottom - (y - yLo) / (yHi - yLo) * plot.height;

    // ---------- grid & ticks ----------
    final gridPaint = Paint()
      ..color = style.grid
      ..strokeWidth = 1 * f;
    for (final y in yTicks) {
      final yy = py(y);
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), gridPaint);
      drawText(canvas, textPainter(y.toStringAsFixed(yDec), tickSize, style.text),
          Offset(plot.left - 6 * f, yy),
          ax: 1, ay: 0.5);
    }
    for (final x in xTicks) {
      final xx = px(x);
      canvas.drawLine(Offset(xx, plot.top), Offset(xx, plot.bottom), gridPaint);
      drawText(canvas, textPainter(x.toStringAsFixed(xDec), tickSize, style.text),
          Offset(xx, plot.bottom + 4 * f),
          ax: 0.5, ay: 0);
    }
    canvas.drawRect(
      plot,
      Paint()
        ..color = style.axis
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * f,
    );

    // Axis titles.
    drawText(
      canvas,
      textPainter('Distance (m)', titleSize, style.text, weight: FontWeight.bold),
      Offset(plot.center.dx, plot.bottom + 4 * f + tickH + 6 * f),
      ax: 0.5,
      ay: 0,
    );
    drawText(
      canvas,
      textPainter('Elevation (m)', titleSize, style.text,
          weight: FontWeight.bold),
      Offset(6 * f, plot.center.dy),
      ax: 0.5,
      ay: 0,
      angle: -math.pi / 2,
    );

    // ---------- ground profile ----------
    final xs = [for (final p in profile) px(p.distance)];
    final ys = [for (final p in profile) py(p.elevation)];

    final fill = Path()..moveTo(xs.first, plot.bottom);
    for (var i = 0; i < xs.length; i++) {
      fill.lineTo(xs[i], ys[i]);
    }
    fill
      ..lineTo(xs.last, plot.bottom)
      ..close();
    canvas.drawPath(fill, Paint()..color = style.groundFill);

    if (dataBands) {
      final drop = Paint()
        ..color = style.subtext.withAlpha(90)
        ..strokeWidth = 0.8 * f;
      for (var i = 0; i < xs.length; i++) {
        canvas.drawLine(Offset(xs[i], ys[i]), Offset(xs[i], plot.bottom), drop);
      }
    }

    final line = Path()..moveTo(xs.first, ys.first);
    for (var i = 1; i < xs.length; i++) {
      line.lineTo(xs[i], ys[i]);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = style.ground
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * f
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    for (var i = 0; i < xs.length; i++) {
      final low = i == lowIdx;
      final c = Offset(xs[i], ys[i]);
      canvas.drawCircle(
          c, (low ? 5 : 4) * f, Paint()..color = low ? style.lowPoint : Colors.white);
      canvas.drawCircle(
        c,
        (low ? 5 : 4) * f,
        Paint()
          ..color = low ? style.lowPoint : style.ground
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * f,
      );
    }

    // ---------- labels above points ----------
    if (label != PointLabel.none) {
      final texts = [
        for (final p in profile)
          label == PointLabel.elevation ? p.elevation.toStringAsFixed(2) : p.note,
      ];
      final has = [for (final t in texts) t.trim().isNotEmpty];
      var maxW = 0.0;
      var minGap = double.infinity;
      double? prevX;
      for (var i = 0; i < texts.length; i++) {
        if (!has[i]) continue;
        maxW = math.max(maxW, textPainter(texts[i], labelSize, style.text).width);
        if (prevX != null) minGap = math.min(minGap, xs[i] - prevX);
        prevX = xs[i];
      }
      final vertical = minGap < maxW + 6 * f;
      final need = vertical ? labelH + 2 * f : maxW + 6 * f;
      final forced = <int>{if (label == PointLabel.elevation) lowIdx};
      final show = _pick(xs, has, forced, need);
      for (var i = 0; i < texts.length; i++) {
        if (!show[i]) continue;
        final low = i == lowIdx && label == PointLabel.elevation;
        final tp = textPainter(
            texts[i], labelSize, low ? style.lowPoint : style.text,
            weight: low ? FontWeight.bold : FontWeight.normal,
            halo: const Color(0xD9FFFFFF));
        if (vertical) {
          drawText(canvas, tp, Offset(xs[i], ys[i] - 8 * f),
              ax: 0, ay: 0.5, angle: -math.pi / 2);
        } else {
          // Keep horizontal labels inside the plot frame.
          final lx = (xs[i] - tp.width / 2)
              .clamp(plot.left + 2 * f, math.max(plot.left + 2 * f, plot.right - tp.width - 2 * f))
              .toDouble();
          drawText(canvas, tp, Offset(lx, ys[i] - 8 * f), ax: 0, ay: 1);
        }
      }
    }

    // ---------- data bands (Distance / RL rows) ----------
    if (dataBands) {
      final bandTop = plot.bottom + axisBlock;
      final headLeft = 4 * f;
      final r1 = Rect.fromLTRB(headLeft, bandTop, plot.right, bandTop + bandRowH);
      final r2 = Rect.fromLTRB(
          headLeft, bandTop + bandRowH, plot.right, bandTop + 2 * bandRowH);
      final border = Paint()
        ..color = style.axis
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * f;
      canvas.drawRect(r1, border);
      canvas.drawRect(r2, border);
      canvas.drawLine(Offset(plot.left, r1.top), Offset(plot.left, r2.bottom), border);
      drawText(
          canvas,
          textPainter('Dist. (m)', labelSize, style.text, weight: FontWeight.bold),
          Offset((headLeft + plot.left) / 2, r1.center.dy),
          ax: 0.5,
          ay: 0.5);
      drawText(
          canvas,
          textPainter('RL (m)', labelSize, style.text, weight: FontWeight.bold),
          Offset((headLeft + plot.left) / 2, r2.center.dy),
          ax: 0.5,
          ay: 0.5);

      final has = List<bool>.filled(xs.length, true);
      final show = _pick(
          xs, has, <int>{0, xs.length - 1, lowIdx}, labelH + 3 * f);
      final tick = Paint()
        ..color = style.axis
        ..strokeWidth = 1 * f;
      for (var i = 0; i < xs.length; i++) {
        if (!show[i]) continue;
        canvas.drawLine(Offset(xs[i], r1.top), Offset(xs[i], r1.top + 5 * f), tick);
        drawText(canvas, textPainter(distStr[i], labelSize, style.text),
            Offset(xs[i], r1.bottom - 6 * f),
            ax: 0, ay: 0.5, angle: -math.pi / 2);
        final low = i == lowIdx;
        drawText(
            canvas,
            textPainter(elevStr[i], labelSize, low ? style.lowPoint : style.text,
                weight: low ? FontWeight.bold : FontWeight.normal),
            Offset(xs[i], r2.bottom - 6 * f),
            ax: 0,
            ay: 0.5,
            angle: -math.pi / 2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SectionPainter oldDelegate) => true;
}
