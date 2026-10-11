import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'section_painter.dart';

String safeFileName(String s) {
  final t = s.trim().replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
  final c = t.replaceAll(RegExp(r'_+'), '_');
  return c.isEmpty ? 'section' : c;
}

String _stamp(DateTime d) =>
    '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';

String elevationBasis(CrossSection s) {
  final ref = s.refElevation;
  if (ref != null) {
    return 'Local reference: first point = ${ref.toStringAsFixed(3)} m';
  }
  return 'GPS altitude (approximate)';
}

String distanceBasis(DistanceMode m) => m == DistanceMode.projected
    ? 'Straight line (projected on first-to-last point line)'
    : 'Walked path (cumulative between points)';

String _csv(String v) {
  if (v.contains(',') || v.contains('"') || v.contains('\n')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

Future<Directory> _exportDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/exports');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Builds the CSV text for a section.
String buildCsv(CrossSection s) {
  final prof = s.profile();
  final sum = SectionSummary.of(prof);
  final b = StringBuffer();
  void row(List<String> cells) => b.writeln(cells.map(_csv).join(','));

  row(['SectionDraw cross-section']);
  row(['Section', s.name]);
  if (s.location.trim().isNotEmpty) row(['Location', s.location]);
  row(['Created', fmtDateTime(s.created)]);
  row(['Exported', fmtDateTime(DateTime.now())]);
  row(['Elevation basis', elevationBasis(s)]);
  row(['Distance method', distanceBasis(s.mode)]);
  row(['Points', '${s.points.length}']);
  if (sum != null) {
    row(['Width (m)', sum.width.toStringAsFixed(2)]);
    row(['Lowest point / bed (m)', sum.lowest.toStringAsFixed(3)]);
    row(['Left bank (m)', sum.leftBank.toStringAsFixed(3)]);
    row(['Right bank (m)', sum.rightBank.toStringAsFixed(3)]);
    row(['Depth below lower bank (m)', sum.depth.toStringAsFixed(3)]);
    row(['Area below lower bank (sq m)', sum.area.toStringAsFixed(3)]);
  }
  b.writeln();
  row([
    'Point',
    'Distance (m)',
    'Elevation (m)',
    'Latitude',
    'Longitude',
    'GPS altitude (m)',
    'H accuracy (m)',
    'V accuracy (m)',
    'Readings averaged',
    'Time',
    'Note',
  ]);
  for (final p in prof) {
    final sp = s.points[p.no - 1];
    row([
      '${p.no}',
      p.distance.toStringAsFixed(2),
      p.elevation.toStringAsFixed(3),
      sp.lat.toStringAsFixed(7),
      sp.lon.toStringAsFixed(7),
      sp.gpsAlt.toStringAsFixed(2),
      sp.hAcc.toStringAsFixed(1),
      sp.vAcc > 0 ? sp.vAcc.toStringAsFixed(1) : '',
      '${sp.samples}',
      fmtDateTime(sp.time),
      sp.note,
    ]);
  }
  return b.toString();
}

Future<File> exportCsv(CrossSection s) async {
  final dir = await _exportDir();
  final f = File(
      '${dir.path}/${safeFileName(s.name)}_${_stamp(DateTime.now())}.csv');
  // BOM so Excel opens UTF-8 (Marathi/Hindi notes) correctly.
  await f.writeAsString('﻿${buildCsv(s)}', flush: true);
  return f;
}

/// Renders the section as a PNG drawing (2000 x 1300 px).
Future<Uint8List> renderSectionPng(CrossSection s) async {
  const w = 2000.0;
  const h = 1300.0;
  const style = ChartStyle.export;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);

  final prof = s.profile();
  final sum = SectionSummary.of(prof);

  // Header.
  SectionPainter.drawText(
    canvas,
    SectionPainter.textPainter('Cross-section: ${s.name}', 44, style.text,
        weight: FontWeight.bold),
    const Offset(40, 28),
  );
  final sub1 = <String>[
    if (s.location.trim().isNotEmpty) s.location.trim(),
    'Surveyed ${fmtDate(s.created)}',
    '${s.points.length} points',
  ].join('   |   ');
  final sub2 =
      'Elevation: ${elevationBasis(s)}   |   Distance: ${distanceBasis(s.mode)}';
  SectionPainter.drawText(
    canvas,
    SectionPainter.textPainter(sub1, 24, style.subtext),
    const Offset(40, 86),
  );
  SectionPainter.drawText(
    canvas,
    SectionPainter.textPainter(sub2, 22, style.subtext),
    const Offset(40, 120),
  );

  // Graph with Distance / RL rows.
  const chartTop = 165.0;
  const footer = 150.0;
  canvas.save();
  canvas.translate(20, chartTop);
  SectionPainter(
    profile: prof,
    style: style,
    label: PointLabel.note,
    dataBands: true,
  ).paint(canvas, const Size(w - 40, h - chartTop - footer));
  canvas.restore();

  // Footer summary.
  if (sum != null) {
    final lineA = 'Width ${sum.width.toStringAsFixed(2)} m     '
        'Lowest (bed) ${sum.lowest.toStringAsFixed(2)} m     '
        'Left bank ${sum.leftBank.toStringAsFixed(2)} m     '
        'Right bank ${sum.rightBank.toStringAsFixed(2)} m';
    final lineB =
        'Depth of bed below lower bank ${sum.depth.toStringAsFixed(2)} m     '
        'Area below lower bank level ${sum.area.toStringAsFixed(2)} sq m';
    SectionPainter.drawText(
      canvas,
      SectionPainter.textPainter(lineA, 26, style.text,
          weight: FontWeight.bold),
      const Offset(40, h - footer + 14),
    );
    SectionPainter.drawText(
      canvas,
      SectionPainter.textPainter(lineB, 26, style.text,
          weight: FontWeight.bold),
      const Offset(40, h - footer + 52),
    );
  }
  SectionPainter.drawText(
    canvas,
    SectionPainter.textPainter(
        'Drawn with SectionDraw on ${fmtDateTime(DateTime.now())}. '
        'Phone GPS elevations are approximate - use for planning only.',
        20,
        style.subtext),
    const Offset(40, h - footer + 100),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(w.toInt(), h.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) throw Exception('Could not create image');
  return data.buffer.asUint8List();
}

Future<File> exportPng(CrossSection s) async {
  final bytes = await renderSectionPng(s);
  final dir = await _exportDir();
  final f = File(
      '${dir.path}/${safeFileName(s.name)}_${_stamp(DateTime.now())}.png');
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

/// Opens the phone's share sheet (WhatsApp, Drive, Gmail, Files, ...).
Future<void> shareFile(File f, String text) async {
  await SharePlus.instance.share(
    ShareParams(files: [XFile(f.path)], text: text),
  );
}
