// SectionDraw data model and survey calculations.
// Pure Dart (no Flutter imports) so it can be unit tested.

import 'dart:math' as math;

/// Mean Earth radius in metres (IUGG).
const double earthRadiusM = 6371008.8;

double _rad(double deg) => deg * math.pi / 180.0;

/// Horizontal (great-circle) distance between two lat/lon points, in metres.
double haversineM(double lat1, double lon1, double lat2, double lon2) {
  final p1 = _rad(lat1);
  final p2 = _rad(lat2);
  final dp = _rad(lat2 - lat1);
  final dl = _rad(lon2 - lon1);
  final a = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * earthRadiusM * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// How horizontal distance is measured along the section.
enum DistanceMode {
  /// Sum of distances between consecutive points (the walked path).
  cumulative,

  /// Each point projected onto the straight line from first to last point.
  projected,
}

class SectionPoint {
  SectionPoint({
    required this.lat,
    required this.lon,
    required this.gpsAlt,
    required this.hAcc,
    required this.vAcc,
    required this.samples,
    required this.time,
    this.note = '',
  });

  final double lat;
  final double lon;

  /// Raw GPS altitude in metres, as reported by the phone.
  final double gpsAlt;

  /// Horizontal accuracy (m, 68% radius) reported by the phone.
  final double hAcc;

  /// Vertical accuracy (m); 0 when the phone does not report it.
  final double vAcc;

  /// Number of GPS readings averaged into this point.
  final int samples;
  final DateTime time;
  String note;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'alt': gpsAlt,
        'hAcc': hAcc,
        'vAcc': vAcc,
        'n': samples,
        't': time.toIso8601String(),
        'note': note,
      };

  factory SectionPoint.fromJson(Map<String, dynamic> j) => SectionPoint(
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        gpsAlt: (j['alt'] as num).toDouble(),
        hAcc: (j['hAcc'] as num? ?? 0).toDouble(),
        vAcc: (j['vAcc'] as num? ?? 0).toDouble(),
        samples: (j['n'] as num? ?? 1).toInt(),
        time: DateTime.tryParse(j['t'] as String? ?? '') ?? DateTime.now(),
        note: j['note'] as String? ?? '',
      );
}

/// One point of the plotted profile (distance, elevation).
class ProfilePoint {
  const ProfilePoint({
    required this.no,
    required this.distance,
    required this.elevation,
    required this.note,
  });

  /// 1-based capture number of the point.
  final int no;
  final double distance;
  final double elevation;
  final String note;
}

class CrossSection {
  CrossSection({
    required this.id,
    required this.name,
    this.location = '',
    required this.created,
    this.refElevation,
    this.mode = DistanceMode.cumulative,
    List<SectionPoint>? points,
  }) : points = points ?? <SectionPoint>[];

  final String id;
  String name;
  String location;
  final DateTime created;

  /// Local reference elevation given to the FIRST point. When set, every
  /// point's elevation = refElevation + (its GPS altitude - first GPS altitude).
  /// When null, raw GPS altitude is used.
  double? refElevation;
  DistanceMode mode;
  final List<SectionPoint> points;

  bool get usesReference => refElevation != null;

  /// Elevation of point [i] (index in capture order).
  double elevationOf(int i) {
    final p = points[i];
    final ref = refElevation;
    if (ref != null && points.isNotEmpty) {
      return ref + (p.gpsAlt - points.first.gpsAlt);
    }
    return p.gpsAlt;
  }

  /// Horizontal distance of every point (capture order) for [m].
  List<double> distances([DistanceMode? m]) {
    final mode0 = m ?? mode;
    final n = points.length;
    if (n == 0) return <double>[];
    if (mode0 == DistanceMode.projected && n >= 2) {
      final proj = _projectedDistances();
      if (proj != null) return proj;
    }
    final out = List<double>.filled(n, 0.0);
    for (var i = 1; i < n; i++) {
      final a = points[i - 1];
      final b = points[i];
      out[i] = out[i - 1] + haversineM(a.lat, a.lon, b.lat, b.lon);
    }
    return out;
  }

  /// Distance along the straight line first point -> last point.
  /// Returns null when first and last points are (almost) the same place.
  List<double>? _projectedDistances() {
    final p0 = points.first;
    final k = math.pi / 180.0 * earthRadiusM;
    final cosLat = math.cos(_rad(p0.lat));
    double xOf(SectionPoint p) => (p.lon - p0.lon) * k * cosLat;
    double yOf(SectionPoint p) => (p.lat - p0.lat) * k;
    final xl = xOf(points.last);
    final yl = yOf(points.last);
    final len = math.sqrt(xl * xl + yl * yl);
    if (len < 0.05) return null;
    final ux = xl / len;
    final uy = yl / len;
    return [for (final p in points) xOf(p) * ux + yOf(p) * uy];
  }

  /// Profile points ordered by distance, ready for plotting/export.
  List<ProfilePoint> profile([DistanceMode? m]) {
    final d = distances(m);
    final out = <ProfilePoint>[
      for (var i = 0; i < points.length; i++)
        ProfilePoint(
          no: i + 1,
          distance: d[i],
          elevation: elevationOf(i),
          note: points[i].note,
        ),
    ];
    out.sort((a, b) {
      final c = a.distance.compareTo(b.distance);
      return c != 0 ? c : a.no.compareTo(b.no);
    });
    return out;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'location': location,
        'created': created.toIso8601String(),
        'ref': refElevation,
        'mode': mode.name,
        'points': [for (final p in points) p.toJson()],
      };

  factory CrossSection.fromJson(Map<String, dynamic> j) => CrossSection(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Section',
        location: j['location'] as String? ?? '',
        created: DateTime.tryParse(j['created'] as String? ?? '') ??
            DateTime.now(),
        refElevation: (j['ref'] as num?)?.toDouble(),
        mode: j['mode'] == 'projected'
            ? DistanceMode.projected
            : DistanceMode.cumulative,
        points: [
          for (final p in (j['points'] as List? ?? const []))
            SectionPoint.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
      );
}

/// Key figures of a cross-section profile.
class SectionSummary {
  const SectionSummary({
    required this.width,
    required this.lowest,
    required this.highest,
    required this.leftBank,
    required this.rightBank,
    required this.depth,
    required this.area,
  });

  /// Horizontal width from first to last point (m).
  final double width;

  /// Lowest elevation (bed) and highest elevation (m).
  final double lowest;
  final double highest;

  /// Elevation at the first (left bank) and last (right bank) point (m).
  final double leftBank;
  final double rightBank;

  /// Depth of the lowest point below the LOWER of the two banks (m).
  final double depth;

  /// Cross-sectional area below the level of the lower bank (m2).
  final double area;

  static SectionSummary? of(List<ProfilePoint> prof) {
    if (prof.length < 2) return null;
    var lo = prof.first.elevation;
    var hi = prof.first.elevation;
    for (final p in prof) {
      lo = math.min(lo, p.elevation);
      hi = math.max(hi, p.elevation);
    }
    final left = prof.first.elevation;
    final right = prof.last.elevation;
    final level = math.min(left, right);
    return SectionSummary(
      width: prof.last.distance - prof.first.distance,
      lowest: lo,
      highest: hi,
      leftBank: left,
      rightBank: right,
      depth: level - lo,
      area: areaBelowLevel(prof, level),
    );
  }
}

/// Area (m2) enclosed between a horizontal water level and the ground
/// profile, counting only parts where the ground is below the level.
double areaBelowLevel(List<ProfilePoint> prof, double level) {
  var area = 0.0;
  for (var i = 1; i < prof.length; i++) {
    final x1 = prof[i - 1].distance;
    final x2 = prof[i].distance;
    final dx = x2 - x1;
    if (dx <= 0) continue;
    final d1 = level - prof[i - 1].elevation; // depth below level
    final d2 = level - prof[i].elevation;
    if (d1 >= 0 && d2 >= 0) {
      area += (d1 + d2) / 2 * dx;
    } else if (d1 > 0 && d2 < 0) {
      final xc = dx * d1 / (d1 - d2);
      area += d1 / 2 * xc;
    } else if (d1 < 0 && d2 > 0) {
      final xc = dx * d2 / (d2 - d1);
      area += d2 / 2 * xc;
    }
  }
  return area;
}

/// "Nice" axis step (1, 2, 2.5, 5 x 10^n) close to [raw].
double niceStep(double raw) {
  if (raw <= 0 || raw.isNaN || raw.isInfinite) return 1;
  final exp = (math.log(raw) / math.ln10).floor();
  final base = math.pow(10, exp).toDouble();
  final f = raw / base;
  double nf;
  if (f <= 1) {
    nf = 1;
  } else if (f <= 2) {
    nf = 2;
  } else if (f <= 2.5) {
    nf = 2.5;
  } else if (f <= 5) {
    nf = 5;
  } else {
    nf = 10;
  }
  return nf * base;
}

String two(int v) => v.toString().padLeft(2, '0');

String fmtDateTime(DateTime d) =>
    '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';

String fmtDate(DateTime d) => '${two(d.day)}-${two(d.month)}-${d.year}';
