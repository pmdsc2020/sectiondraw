import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sectiondraw/models.dart';

SectionPoint _pt(double lat, double lon, double alt) => SectionPoint(
      lat: lat,
      lon: lon,
      gpsAlt: alt,
      hAcc: 3,
      vAcc: 5,
      samples: 1,
      time: DateTime(2026, 10, 11),
    );

void main() {
  const lat0 = 21.37;
  const lon0 = 74.24;
  // Degrees of longitude per metre going east at lat0.
  final degPerM =
      1 / (math.pi / 180 * earthRadiusM * math.cos(lat0 * math.pi / 180));

  CrossSection vSection({double? ref}) => CrossSection(
        id: 't',
        name: 'Test',
        created: DateTime(2026, 10, 11),
        refElevation: ref,
        points: [
          for (final e in const [
            [0.0, 210.0],
            [2.0, 209.0],
            [4.0, 208.0],
            [6.0, 209.0],
            [8.0, 210.0],
          ])
            _pt(lat0, lon0 + e[0] * degPerM, e[1]),
        ],
      );

  test('haversine: 1 degree of latitude is about 111.2 km', () {
    expect(haversineM(21, 74, 22, 74), closeTo(111195, 60));
  });

  test('cumulative distance from first point', () {
    final d = vSection().distances(DistanceMode.cumulative);
    expect(d.first, 0);
    expect(d.last, closeTo(8, 0.01));
    expect(d[2], closeTo(4, 0.01));
  });

  test('reference elevation shifts all points by the same amount', () {
    final s = vSection(ref: 100);
    expect(s.elevationOf(0), closeTo(100, 1e-9));
    expect(s.elevationOf(2), closeTo(98, 1e-9));
    expect(s.elevationOf(4), closeTo(100, 1e-9));
  });

  test('summary: depth and area below lower bank of a V section', () {
    final sum = SectionSummary.of(vSection(ref: 100).profile())!;
    expect(sum.width, closeTo(8, 0.01));
    expect(sum.lowest, closeTo(98, 1e-9));
    expect(sum.depth, closeTo(2, 1e-9));
    expect(sum.area, closeTo(8, 0.01));
  });

  test('projected distance removes sideways zig-zag', () {
    final s = CrossSection(
      id: 'z',
      name: 'Zig',
      created: DateTime(2026, 10, 11),
      points: [
        _pt(lat0, lon0, 10),
        _pt(lat0 + 1 / 111195.0, lon0 + 5 * degPerM, 9), // 1 m north
        _pt(lat0, lon0 + 10 * degPerM, 10),
      ],
    );
    final proj = s.distances(DistanceMode.projected);
    final cum = s.distances(DistanceMode.cumulative);
    expect(proj[1], closeTo(5, 0.02));
    expect(proj[2], closeTo(10, 0.02));
    expect(cum[2], greaterThan(10.1));
  });

  test('nice axis steps', () {
    expect(niceStep(0.37), 0.5);
    expect(niceStep(1.7), 2);
    expect(niceStep(2.2), 2.5);
    expect(niceStep(7), 10);
  });

  test('JSON round trip keeps points and reference', () {
    final s = vSection(ref: 100);
    s.points[1].note = 'Bed';
    final back = CrossSection.fromJson(s.toJson());
    expect(back.points.length, 5);
    expect(back.refElevation, 100);
    expect(back.points[1].note, 'Bed');
  });
}
