import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'dialogs.dart';
import 'export.dart';
import 'models.dart';
import 'section_painter.dart';
import 'storage.dart';

class SectionScreen extends StatefulWidget {
  const SectionScreen({super.key, required this.store, required this.section});

  final SectionStore store;
  final CrossSection section;

  @override
  State<SectionScreen> createState() => _SectionScreenState();
}

enum _GpsProblem { none, serviceOff, denied, deniedForever, error }

const _cardBorder = Color(0xFFDDDDDD);
const _muted = TextStyle(fontSize: 13, color: Colors.black54);

class _SectionScreenState extends State<SectionScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final TextEditingController _note = TextEditingController();

  StreamSubscription<Position>? _sub;
  StreamSubscription<ServiceStatus>? _serviceSub;
  Timer? _ticker;
  Timer? _captureTimer;

  Position? _pos;
  DateTime? _posAt;
  _GpsProblem _problem = _GpsProblem.none;
  String _problemText = '';
  bool _starting = false;

  bool _capturing = false;
  int _captureLeft = 0;
  final List<Position> _samples = <Position>[];
  bool _exporting = false;

  CrossSection get s => widget.section;
  SectionStore get store => widget.store;

  // ---------------------------------------------------------------- lifecycle

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startGps();
    try {
      _serviceSub = Geolocator.getServiceStatusStream().listen((st) {
        if (st == ServiceStatus.enabled && _problem == _GpsProblem.serviceOff) {
          _startGps();
        }
      });
    } catch (_) {
      // Not supported on this platform; the TRY AGAIN button still works.
    }
    // Refresh the screen when GPS fixes stop arriving (shows "no new fix").
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final at = _posAt;
      if (mounted &&
          at != null &&
          DateTime.now().difference(at).inSeconds >= 3) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _serviceSub?.cancel();
    _ticker?.cancel();
    _captureTimer?.cancel();
    _tabs.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from phone settings: try GPS again.
    if (state == AppLifecycleState.resumed && _problem != _GpsProblem.none) {
      _startGps();
    }
  }

  // ---------------------------------------------------------------- GPS

  LocationSettings _settings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        forceLocationManager: true, // raw GPS chip readings incl. altitude
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
  }

  void _setProblem(_GpsProblem p, String text) {
    if (!mounted) return;
    setState(() {
      _problem = p;
      _problemText = text;
    });
  }

  Future<void> _startGps() async {
    if (_starting) return;
    _starting = true;
    try {
      await _sub?.cancel();
      _sub = null;
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setProblem(_GpsProblem.serviceOff,
            'Location (GPS) is switched off on this phone.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _setProblem(_GpsProblem.deniedForever,
            'Location permission is blocked. Allow "Location" for SectionDraw in App settings.');
        return;
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.unableToDetermine) {
        _setProblem(_GpsProblem.denied,
            'Location permission is needed to capture points.');
        return;
      }
      _setProblem(_GpsProblem.none, '');
      _sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(
        _onPosition,
        onError: (Object e) {
          if (e is LocationServiceDisabledException) {
            _setProblem(
                _GpsProblem.serviceOff, 'Location (GPS) was switched off.');
          } else {
            _setProblem(_GpsProblem.error, 'GPS error: $e');
          }
        },
      );
    } catch (e) {
      _setProblem(_GpsProblem.error, 'GPS error: $e');
    } finally {
      _starting = false;
    }
  }

  void _onPosition(Position p) {
    if (!mounted) return;
    setState(() {
      _pos = p;
      _posAt = DateTime.now();
      _problem = _GpsProblem.none;
      if (_capturing) _samples.add(p);
    });
  }

  int get _fixAge {
    final at = _posAt;
    return at == null ? 9999 : DateTime.now().difference(at).inSeconds;
  }

  // ---------------------------------------------------------------- actions

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _capture() async {
    if (_capturing) return;
    final p = _pos;
    if (p == null) {
      _snack('No GPS fix yet. Wait until accuracy is shown.');
      return;
    }
    if (_fixAge > 10) {
      _snack('GPS signal lost. Move to open sky and wait.');
      return;
    }
    if (p.accuracy > 10) {
      final ok = await confirm(
        context,
        title: 'Poor GPS accuracy',
        message:
            'Accuracy is ±${p.accuracy.toStringAsFixed(1)} m (worse than 10 m). '
            'Capture anyway?',
        yes: 'CAPTURE',
      );
      if (!ok || !mounted) return;
    }
    final secs = store.avgSeconds;
    if (secs <= 0) {
      _addPoint(<Position>[p]);
      return;
    }
    setState(() {
      _capturing = true;
      _captureLeft = secs;
      _samples.clear();
    });
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_captureLeft > 1) {
        setState(() => _captureLeft--);
        return;
      }
      t.cancel();
      final got = List<Position>.from(_samples);
      setState(() {
        _capturing = false;
        _captureLeft = 0;
        _samples.clear();
      });
      if (got.isEmpty) {
        final last = _pos;
        if (last != null && _fixAge <= 5) got.add(last);
      }
      if (got.isEmpty) {
        _snack('No GPS readings received. Try again.');
        return;
      }
      _addPoint(got);
    });
  }

  void _addPoint(List<Position> got) {
    var lat = 0.0, lon = 0.0, alt = 0.0, h = 0.0, v = 0.0;
    var vn = 0;
    for (final q in got) {
      lat += q.latitude;
      lon += q.longitude;
      alt += q.altitude;
      h += q.accuracy;
      if (q.altitudeAccuracy > 0) {
        v += q.altitudeAccuracy;
        vn++;
      }
    }
    final n = got.length;
    final pt = SectionPoint(
      lat: lat / n,
      lon: lon / n,
      gpsAlt: alt / n,
      hAcc: h / n,
      vAcc: vn > 0 ? v / vn : 0,
      samples: n,
      time: DateTime.now(),
      note: _note.text.trim(),
    );
    setState(() {
      s.points.add(pt);
      _note.clear();
    });
    store.save();
    final i = s.points.length;
    _snack(n > 1 ? 'Point $i saved (average of $n readings)' : 'Point $i saved');
  }

  Future<void> _undoLast() async {
    if (s.points.isEmpty) return;
    final n = s.points.length;
    final ok = await confirm(
      context,
      title: 'Delete point $n?',
      message: 'The last captured point will be removed.',
      yes: 'DELETE',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => s.points.removeLast());
    store.save();
  }

  Future<void> _deletePoint(int i) async {
    final msg = (i == 0 && s.usesReference && s.points.length > 1)
        ? 'Point 1 carries the reference elevation. After deleting it, '
            'point 2 becomes the reference point.'
        : 'Point ${i + 1} will be removed.';
    final ok = await confirm(context,
        title: 'Delete point ${i + 1}?', message: msg, yes: 'DELETE', danger: true);
    if (!ok || !mounted) return;
    setState(() => s.points.removeAt(i));
    store.save();
  }

  Future<void> _editNote(int i) async {
    final v = await askText(context,
        title: 'Note for point ${i + 1}',
        initial: s.points[i].note,
        label: 'Note (e.g. Left bank, Bed)');
    if (v == null || !mounted) return;
    setState(() => s.points[i].note = v.trim());
    store.save();
  }

  Future<void> _setReference() async {
    final v = await askText(
      context,
      title: 'Reference elevation',
      initial: s.refElevation?.toStringAsFixed(3) ?? '',
      label: 'Elevation of FIRST point (m)',
      help: 'Other points = this value + their GPS height difference from '
          'point 1. Leave empty to use raw GPS altitude.',
      numeric: true,
    );
    if (v == null || !mounted) return;
    final t = v.trim();
    if (t.isEmpty) {
      setState(() => s.refElevation = null);
      store.save();
      return;
    }
    final d = parseNumber(t);
    if (d == null) {
      _snack('"$t" is not a valid number');
      return;
    }
    setState(() => s.refElevation = d);
    store.save();
  }

  Future<void> _rename() async {
    final v = await askText(context,
        title: 'Rename section', initial: s.name, label: 'Section name');
    if (v == null || v.trim().isEmpty || !mounted) return;
    setState(() => s.name = v.trim());
    store.save();
  }

  Future<void> _export({required bool png}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final f = png ? await exportPng(s) : await exportCsv(s);
      await shareFile(f, '${s.name} - cross-section');
    } catch (e) {
      _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(s.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Rename',
            onPressed: _rename,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xB3FFFFFF),
          indicatorColor: Colors.white,
          indicatorWeight: 4,
          labelStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.gps_fixed), text: 'CAPTURE'),
            Tab(icon: Icon(Icons.format_list_numbered), text: 'POINTS'),
            Tab(icon: Icon(Icons.show_chart), text: 'GRAPH'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        physics: const NeverScrollableScrollPhysics(),
        children: [_captureTab(), _pointsTab(), _graphTab()],
      ),
    );
  }

  Widget _box({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _cardBorder),
        ),
        child: child,
      );

  Widget _stat(String label, String value) => _box(
        child: Column(
          children: [
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

  Widget _emptyMsg(String t) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(t,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18)),
        ),
      );

  // ----- Capture tab

  Widget _captureTab() {
    final p = _pos;
    final last = s.points.isEmpty ? null : s.points.last;
    double? fromLast;
    if (p != null && last != null) {
      fromLast = haversineM(last.lat, last.lon, p.latitude, p.longitude);
    }
    final d = s.distances(DistanceMode.cumulative);
    final walked = d.isEmpty ? 0.0 : d.last;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
      children: [
        _gpsCard(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _stat('POINTS', '${s.points.length}')),
            const SizedBox(width: 8),
            Expanded(
              child: _stat('FROM LAST',
                  fromLast == null ? '—' : '${fromLast.toStringAsFixed(1)} m'),
            ),
            const SizedBox(width: 8),
            Expanded(child: _stat('WALKED', '${walked.toStringAsFixed(1)} m')),
          ],
        ),
        const SizedBox(height: 12),
        _refCard(),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(
            labelText: 'Note for next point (optional)',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 2,
          children: [
            for (final t in const ['Left bank', 'Bed', 'Water edge', 'Right bank'])
              ActionChip(
                label: Text(t, style: const TextStyle(fontSize: 15)),
                onPressed: () => setState(() => _note.text = t),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('Average:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Expanded(
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment<int>(value: 0, label: Text('Off')),
                  ButtonSegment<int>(value: 5, label: Text('5 sec')),
                  ButtonSegment<int>(value: 10, label: Text('10 sec')),
                ],
                selected: <int>{store.avgSeconds},
                onSelectionChanged: _capturing
                    ? null
                    : (v) {
                        setState(() => store.avgSeconds = v.first);
                        store.save();
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 92,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor:
                  _capturing ? const Color(0xFFEF6C00) : const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
              textStyle:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: _capture,
            icon: _capturing
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: Colors.white),
                  )
                : const Icon(Icons.add_location_alt, size: 34),
            label: Text(_capturing
                ? 'AVERAGING… $_captureLeft s'
                : 'CAPTURE POINT ${s.points.length + 1}'),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (s.points.isEmpty || _capturing) ? null : _undoLast,
                icon: const Icon(Icons.undo),
                label: const Text('UNDO LAST'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _tabs.animateTo(2),
                icon: const Icon(Icons.show_chart),
                label: const Text('GRAPH'),
              ),
            ),
          ],
        ),
        if (last != null) ...[
          const SizedBox(height: 12),
          Text(
            'Last: point ${s.points.length}  ·  '
            'elev ${s.elevationOf(s.points.length - 1).toStringAsFixed(2)} m  ·  '
            '±${last.hAcc.toStringAsFixed(1)} m'
            '${last.note.isEmpty ? '' : '  ·  ${last.note}'}',
            style: const TextStyle(fontSize: 15, color: Colors.black87),
          ),
        ],
        const SizedBox(height: 10),
        const Text(
          'Walk from LEFT bank to RIGHT bank (facing downstream). Hold the '
          'phone at the same height for every point and let accuracy settle '
          'before capturing.',
          style: _muted,
        ),
      ],
    );
  }

  Widget _gpsCard() {
    if (_problem != _GpsProblem.none) return _problemCard();
    final p = _pos;
    final age = _fixAge;
    Color bg;
    String status;
    if (p == null) {
      bg = const Color(0xFF616161);
      status = 'WAITING FOR GPS…';
    } else if (age >= 3) {
      bg = const Color(0xFF616161);
      status = 'NO NEW FIX (${age}s)';
    } else if (p.accuracy <= 5) {
      bg = const Color(0xFF2E7D32);
      status = 'GOOD';
    } else if (p.accuracy <= 10) {
      bg = const Color(0xFFE65100);
      status = 'FAIR';
    } else {
      bg = const Color(0xFFC62828);
      status = 'POOR';
    }
    return Card(
      color: bg,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.gps_fixed, color: Colors.white),
                const SizedBox(width: 8),
                const Text('GPS ACCURACY',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(status,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              p == null ? '— —' : '± ${p.accuracy.toStringAsFixed(1)} m',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.bold),
            ),
            if (p != null) ...[
              Text(
                'Vertical ${p.altitudeAccuracy > 0 ? '± ${p.altitudeAccuracy.toStringAsFixed(1)} m' : 'n/a'}'
                '   ·   GPS alt ${p.altitude.toStringAsFixed(1)} m',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 2),
              Text(
                '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}',
                style: const TextStyle(color: Color(0xDDFFFFFF), fontSize: 15),
              ),
            ] else
              const Text(
                'Stand in open sky. The first fix can take up to a minute.',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
          ],
        ),
      ),
    );
  }

  Widget _problemCard() {
    return Card(
      color: const Color(0xFFFFF3E0),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.location_off,
                    color: Color(0xFFC62828), size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_problemText,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_problem == _GpsProblem.serviceOff)
              FilledButton(
                onPressed: () => Geolocator.openLocationSettings(),
                child: const Text('TURN ON LOCATION'),
              ),
            if (_problem == _GpsProblem.deniedForever)
              FilledButton(
                onPressed: () => Geolocator.openAppSettings(),
                child: const Text('OPEN APP SETTINGS'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _startGps,
              child: const Text('TRY AGAIN'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _refCard() {
    final ref = s.refElevation;
    return _box(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ELEVATION BASIS',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54)),
                Text(
                  ref == null
                      ? 'Raw GPS altitude'
                      : 'Point 1 = ${ref.toStringAsFixed(3)} m (local)',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: _setReference,
            child: const Text('SET REF'),
          ),
        ],
      ),
    );
  }

  // ----- Points tab

  Widget _pointsTab() {
    if (s.points.isEmpty) {
      return _emptyMsg('No points yet.\n\nGo to CAPTURE and record the first '
          'point on the left bank.');
    }
    final d = s.distances();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
      children: [
        _refCard(),
        const SizedBox(height: 6),
        Text(
          s.mode == DistanceMode.cumulative
              ? 'Distance: walked path from point 1'
              : 'Distance: along straight line point 1 → last point',
          style: _muted,
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < s.points.length; i++) _pointTile(i, d[i]),
      ],
    );
  }

  Widget _pointTile(int i, double dist) {
    final p = s.points[i];
    final info = <String>[
      '±${p.hAcc.toStringAsFixed(1)} m',
      if (p.samples > 1) 'avg ${p.samples}',
      fmtDateTime(p.time).substring(11),
      if (p.note.isNotEmpty) p.note,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFF5D4037),
          foregroundColor: Colors.white,
          child: Text('${i + 1}',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
        title: Text(
          '${dist.toStringAsFixed(2)} m   ·   El ${s.elevationOf(i).toStringAsFixed(2)} m',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(info.join('  ·  '), style: const TextStyle(fontSize: 14)),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 28),
          onSelected: (a) {
            if (a == 'note') {
              _editNote(i);
            } else {
              _deletePoint(i);
            }
          },
          itemBuilder: (_) => const <PopupMenuEntry<String>>[
            PopupMenuItem<String>(value: 'note', child: Text('Edit note')),
            PopupMenuItem<String>(value: 'delete', child: Text('Delete point')),
          ],
        ),
      ),
    );
  }

  // ----- Graph tab

  Widget _graphTab() {
    final prof = s.profile();
    final sum = SectionSummary.of(prof);
    if (sum == null) {
      return _emptyMsg('Capture at least 2 points to see the cross-section '
          'graph.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
      children: [
        SegmentedButton<DistanceMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<DistanceMode>(
              value: DistanceMode.cumulative,
              label: Text('Walked path'),
              icon: Icon(Icons.timeline),
            ),
            ButtonSegment<DistanceMode>(
              value: DistanceMode.projected,
              label: Text('Straight line'),
              icon: Icon(Icons.straighten),
            ),
          ],
          selected: <DistanceMode>{s.mode},
          onSelectionChanged: (v) {
            setState(() => s.mode = v.first);
            store.save();
          },
        ),
        const SizedBox(height: 4),
        Text(
          s.mode == DistanceMode.cumulative
              ? 'Distance = sum of distances between consecutive points.'
              : 'Distance measured along the straight line from point 1 to '
                  'the last point (removes zig-zag of walking).',
          style: _muted,
        ),
        const SizedBox(height: 10),
        Container(
          height: 380,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cardBorder),
          ),
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: SizedBox.expand(
              child: CustomPaint(
                painter: SectionPainter(
                  profile: prof,
                  style: ChartStyle.screen,
                  label: PointLabel.elevation,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text('Pinch to zoom. Labels = elevation (m). Blue = lowest point.',
            style: _muted),
        const SizedBox(height: 12),
        _summaryGrid(sum),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 64,
                child: FilledButton.icon(
                  onPressed: _exporting ? null : () => _export(png: false),
                  icon: const Icon(Icons.table_chart),
                  label: const Text('EXPORT CSV'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 64,
                child: FilledButton.icon(
                  onPressed: _exporting ? null : () => _export(png: true),
                  icon: const Icon(Icons.image),
                  label: const Text('EXPORT PNG'),
                ),
              ),
            ),
          ],
        ),
        if (_exporting)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 8),
        const Text(
          'Export opens the share menu: save to Drive / Files, or send by '
          'WhatsApp or Gmail. A copy is also kept inside the app.',
          style: _muted,
        ),
      ],
    );
  }

  Widget _summaryGrid(SectionSummary m) {
    final items = <List<String>>[
      ['WIDTH', '${m.width.toStringAsFixed(2)} m'],
      ['LOWEST (BED)', '${m.lowest.toStringAsFixed(2)} m'],
      ['LEFT BANK', '${m.leftBank.toStringAsFixed(2)} m'],
      ['RIGHT BANK', '${m.rightBank.toStringAsFixed(2)} m'],
      ['BED BELOW LOWER BANK', '${m.depth.toStringAsFixed(2)} m'],
      ['AREA BELOW LOWER BANK', '${m.area.toStringAsFixed(2)} m²'],
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final it in items)
              SizedBox(width: w, child: _stat(it[0], it[1])),
          ],
        );
      },
    );
  }
}
