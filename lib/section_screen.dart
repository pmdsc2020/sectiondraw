import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'dialogs.dart';
import 'export.dart';
import 'home_screen.dart' show menuItem;
import 'models.dart';
import 'section_painter.dart';
import 'storage.dart';
import 'theme.dart';
import 'ui/buttons.dart';
import 'ui/glass.dart';
import 'ui/motion.dart';
import 'ui/widgets.dart';

class SectionScreen extends StatefulWidget {
  const SectionScreen({super.key, required this.store, required this.section});

  final SectionStore store;
  final CrossSection section;

  @override
  State<SectionScreen> createState() => _SectionScreenState();
}

enum _GpsProblem { none, serviceOff, denied, deniedForever, error }

class _SectionScreenState extends State<SectionScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final TextEditingController _note = TextEditingController();
  final TransformationController _zoom = TransformationController();

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
  bool _exportingPng = false;

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
    _zoom.dispose();
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
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
        content: Text(msg),
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
        yes: 'Capture',
        icon: LucideIcons.triangleAlert,
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
    HapticFeedback.mediumImpact();
    final i = s.points.length;
    _snack(
        n > 1 ? 'Point $i saved (average of $n readings)' : 'Point $i saved');
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
        title: 'Delete point ${i + 1}?',
        message: msg,
        yes: 'DELETE',
        danger: true);
    if (!ok || !mounted) return;
    setState(() => s.points.removeAt(i));
    store.save();
  }

  Future<void> _editNote(int i) async {
    final v = await askText(context,
        title: 'Note for point ${i + 1}',
        initial: s.points[i].note,
        label: 'Note (e.g. Left bank, Bed)',
        icon: LucideIcons.notebookPen);
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
      icon: LucideIcons.arrowDownToLine,
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
    setState(() {
      _exporting = true;
      _exportingPng = png;
    });
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

  Future<void> _more(String a) async {
    switch (a) {
      case 'rename':
        await _rename();
      case 'location':
        final v = await askText(context,
            title: 'Village / location',
            initial: s.location,
            label: 'Village, nala, chainage...',
            icon: LucideIcons.mapPin);
        if (v == null || !mounted) return;
        setState(() => s.location = v.trim());
        store.save();
      case 'ref':
        await _setReference();
      case 'csv':
        await _export(png: false);
      case 'png':
        await _export(png: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = [
      if (s.location.trim().isNotEmpty) s.location.trim(),
      '${s.points.length} point${s.points.length == 1 ? '' : 's'}',
    ].join('  ·  ');
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 4),
                child: Row(
                  children: [
                    IconPill(
                      icon: LucideIcons.arrowLeft,
                      tooltip: 'Back to sections',
                      motion: IconMotion.nudge,
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: display(21, color: c.text)),
                          ),
                          Text(sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: c.muted)),
                        ],
                      ),
                    ),
                    IconPill(
                      icon: LucideIcons.pencil,
                      tooltip: 'Rename section',
                      motion: IconMotion.wiggle,
                      onPressed: _rename,
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More actions',
                      icon: Icon(LucideIcons.ellipsisVertical, color: c.text),
                      onSelected: _more,
                      itemBuilder: (ctx) => [
                        menuItem(ctx, 'rename', LucideIcons.pencil, 'Rename'),
                        menuItem(ctx, 'location', LucideIcons.mapPin,
                            'Edit location'),
                        menuItem(ctx, 'ref', LucideIcons.arrowDownToLine,
                            'Reference elevation'),
                        if (s.points.length >= 2) ...[
                          const PopupMenuDivider(),
                          menuItem(ctx, 'csv', LucideIcons.fileSpreadsheet,
                              'Export CSV'),
                          menuItem(
                              ctx, 'png', LucideIcons.fileImage, 'Export PNG'),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              _tabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _page(_captureTab()),
                    _page(_pointsTab()),
                    _page(_graphTab(), maxWidth: 980),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Centres tab content and caps its width on tablets / desktop.
  Widget _page(Widget child, {double maxWidth = 720}) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );

  Widget _tabBar() {
    final c = context.colors;
    Tab tab(IconData icon, String label) => Tab(
          height: 50,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 7),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: GlassCard(
          padding: const EdgeInsets.all(5),
          radius: 20,
          child: TabBar(
            controller: _tabs,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            splashBorderRadius: BorderRadius.circular(15),
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(
                  colors: [Color(0xFF047857), Color(0xFF0E7490)]),
              boxShadow: [BoxShadow(color: c.glow, blurRadius: 14)],
            ),
            labelColor: Colors.white,
            unselectedLabelColor: c.muted,
            labelStyle: const TextStyle(
                fontFamily: kBodyFont,
                fontSize: 14.5,
                fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(
                fontFamily: kBodyFont,
                fontSize: 14.5,
                fontWeight: FontWeight.w600),
            tabs: [
              tab(LucideIcons.crosshair, 'Capture'),
              tab(LucideIcons.listOrdered, 'Points'),
              tab(LucideIcons.chartSpline, 'Graph'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyMsg(IconData icon, String title, String t,
          {String? action, VoidCallback? onAction}) =>
      EmptyState(
        icon: icon,
        title: title,
        message: t,
        actionLabel: action,
        actionIcon: LucideIcons.crosshair,
        onAction: onAction,
      );

  // ----- Capture tab

  Widget _captureTab() {
    final c = context.colors;
    final p = _pos;
    final last = s.points.isEmpty ? null : s.points.last;
    double? fromLast;
    if (p != null && last != null) {
      fromLast = haversineM(last.lat, last.lon, p.latitude, p.longitude);
    }
    final d = s.distances(DistanceMode.cumulative);
    final walked = d.isEmpty ? 0.0 : d.last;
    final secs = store.avgSeconds;
    const notes = <(String, IconData)>[
      ('Left bank', LucideIcons.arrowRightFromLine),
      ('Bed', LucideIcons.arrowDownToLine),
      ('Water edge', LucideIcons.waves),
      ('Right bank', LucideIcons.arrowLeftToLine),
    ];

    var i = 0;
    Widget item(Widget w) => FadeSlideIn(index: i++, child: w);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 36),
      children: [
        item(_gpsCard()),
        const SizedBox(height: 12),
        item(IntrinsicHeight(
            child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: StatTile(
                icon: LucideIcons.circleDot,
                label: 'Points',
                value: '${s.points.length}',
                onTap: s.points.isEmpty ? null : () => _tabs.animateTo(1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                icon: LucideIcons.moveHorizontal,
                label: 'From last',
                value:
                    fromLast == null ? '—' : '${fromLast.toStringAsFixed(1)} m',
                color: c.water,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                icon: LucideIcons.footprints,
                label: 'Walked',
                value: '${walked.toStringAsFixed(1)} m',
                color: c.accent,
              ),
            ),
          ],
        ))),
        const SizedBox(height: 12),
        item(_refCard()),
        const SizedBox(height: 12),
        item(GlassCard(
          blur: false,
          strong: true,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _note,
                onChanged: (_) => setState(() {}),
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Note for next point (optional)',
                  prefixIcon:
                      Icon(LucideIcons.notebookPen, size: 20, color: c.muted),
                  suffixIcon: _note.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear note',
                          icon: Icon(LucideIcons.x, size: 20, color: c.text),
                          onPressed: () => setState(_note.clear),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (t, icon) in notes)
                    SelectChip(
                      label: t,
                      icon: icon,
                      selected: _note.text == t,
                      onTap: () =>
                          setState(() => _note.text = _note.text == t ? '' : t),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(LucideIcons.timer, size: 18, color: c.muted),
                  const SizedBox(width: 8),
                  Text('Averaging',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.text)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment<int>(value: 0, label: Text('Off')),
                        ButtonSegment<int>(value: 5, label: Text('5 s')),
                        ButtonSegment<int>(value: 10, label: Text('10 s')),
                      ],
                      selected: <int>{secs},
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
            ],
          ),
        )),
        const SizedBox(height: 16),
        item(TweenAnimationBuilder<double>(
          tween: Tween(
            begin: 0,
            end: _capturing && secs > 0 ? (secs - _captureLeft + 1) / secs : 0,
          ),
          duration: _capturing ? const Duration(seconds: 1) : Duration.zero,
          builder: (context, v, _) => GlowButton(
            height: 92,
            fontSize: 21,
            iconMotion: IconMotion.bounce,
            colors: _capturing
                ? const [Color(0xFFB45309), Color(0xFFC2410C)]
                : null,
            progress: _capturing ? v : null,
            icon: LucideIcons.mapPinPlus,
            label: _capturing
                ? 'Averaging… $_captureLeft s'
                : 'Capture point ${s.points.length + 1}',
            semanticLabel: _capturing
                ? 'Averaging GPS readings, $_captureLeft seconds left'
                : 'Capture point ${s.points.length + 1}',
            onPressed: _capturing ? () {} : _capture,
          ),
        )),
        const SizedBox(height: 12),
        item(Row(
          children: [
            Expanded(
              child: GhostButton(
                label: 'Undo last',
                icon: LucideIcons.undo2,
                iconMotion: IconMotion.wiggle,
                color: c.danger,
                onPressed: (s.points.isEmpty || _capturing) ? null : _undoLast,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GhostButton(
                label: 'View graph',
                icon: LucideIcons.chartSpline,
                iconMotion: IconMotion.nudge,
                onPressed: () => _tabs.animateTo(2),
              ),
            ),
          ],
        )),
        if (last != null) ...[
          const SizedBox(height: 12),
          item(_lastPointCard(last)),
        ],
        const SizedBox(height: 14),
        item(const HintText(
          'Walk from LEFT bank to RIGHT bank (facing downstream). Hold the '
          'phone at the same height for every point and let accuracy settle '
          'before capturing.',
          icon: LucideIcons.lightbulb,
        )),
      ],
    );
  }

  Widget _lastPointCard(SectionPoint last) {
    final c = context.colors;
    final n = s.points.length;
    return GlassCard(
      blur: false,
      strong: true,
      onTap: () => _tabs.animateTo(1),
      semanticLabel: 'Last point $n. Open points list',
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        children: [
          _numberBadge(n, false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LAST POINT', style: eyebrow(c.muted)),
                const SizedBox(height: 2),
                Text(
                  'El ${s.elevationOf(n - 1).toStringAsFixed(2)} m  ·  '
                  '±${last.hAcc.toStringAsFixed(1)} m',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                      fontFeatures: kTabular),
                ),
                if (last.note.isNotEmpty)
                  Text(last.note,
                      style: TextStyle(fontSize: 14, color: c.muted)),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, color: c.muted),
        ],
      ),
    );
  }

  Widget _gpsCard() {
    if (_problem != _GpsProblem.none) return _problemCard();
    final c = context.colors;
    final p = _pos;
    final age = _fixAge;
    Color bg;
    String status;
    IconData statusIcon;
    if (p == null) {
      bg = c.idle;
      status = 'Waiting for GPS…';
      statusIcon = LucideIcons.satellite;
    } else if (age >= 3) {
      bg = c.idle;
      status = 'No new fix (${age}s)';
      statusIcon = LucideIcons.signalLow;
    } else if (p.accuracy <= 5) {
      bg = c.good;
      status = 'Good';
      statusIcon = LucideIcons.shieldCheck;
    } else if (p.accuracy <= 10) {
      bg = c.fair;
      status = 'Fair';
      statusIcon = LucideIcons.signalMedium;
    } else {
      bg = c.poor;
      status = 'Poor';
      statusIcon = LucideIcons.triangleAlert;
    }
    final live = p != null && age < 3;
    // 0 m -> full bar, 20 m or worse -> empty.
    final quality = p == null ? 0.0 : (1 - p.accuracy / 20).clamp(0.04, 1.0);
    const fg = Colors.white;
    const fgSoft = Color(0xE6FFFFFF);

    return Semantics(
      liveRegion: true,
      label: p == null
          ? 'GPS: $status'
          : 'GPS accuracy plus or minus ${p.accuracy.toStringAsFixed(1)} metres, $status',
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.slow),
        curve: Motion.emphasized,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bg, Color.alphaBlend(Colors.black.withAlpha(50), bg)],
          ),
          boxShadow: [
            BoxShadow(
                color: bg.withAlpha(90),
                blurRadius: 24,
                offset: const Offset(0, 10)),
          ],
        ),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Radar(
                      active: live,
                      child: const Icon(LucideIcons.locateFixed,
                          color: fg, size: 20)),
                  const SizedBox(width: 10),
                  Text('GPS ACCURACY', style: eyebrow(fgSoft)),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: Motion.of(context, Motion.medium),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerRight,
                      children: [...previous, if (current != null) current],
                    ),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: a, child: child),
                    ),
                    child: Container(
                      key: ValueKey(status),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(46),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 15, color: fg),
                          const SizedBox(width: 6),
                          Text(status,
                              style: const TextStyle(
                                  color: fg,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: RollingText(
                  p == null ? '— —' : '± ${p.accuracy.toStringAsFixed(1)} m',
                  style: display(46, color: fg, letterSpacing: -1.5),
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  height: 7,
                  color: Colors.black.withAlpha(50),
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration: Motion.of(context, Motion.slow),
                    curve: Motion.emphasized,
                    widthFactor: quality,
                    heightFactor: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: fg,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (p != null) ...[
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _gpsFact(LucideIcons.arrowUpDown,
                        'Vertical ${p.altitudeAccuracy > 0 ? '± ${p.altitudeAccuracy.toStringAsFixed(1)} m' : 'n/a'}'),
                    _gpsFact(LucideIcons.mountain,
                        'GPS alt ${p.altitude.toStringAsFixed(1)} m'),
                  ],
                ),
                const SizedBox(height: 6),
                _gpsFact(LucideIcons.mapPin,
                    '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}'),
              ] else
                const Text(
                  'Stand in open sky. The first fix can take up to a minute.',
                  style: TextStyle(color: fg, fontSize: 15, height: 1.4),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gpsFact(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xE6FFFFFF)),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  fontFeatures: kTabular)),
        ],
      );

  Widget _problemCard() {
    final c = context.colors;
    return GlassCard(
      strong: true,
      tint: c.danger,
      radius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: c.danger.withAlpha(36),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.locateOff, color: c.danger, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_problemText,
                    style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: c.text)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_problem == _GpsProblem.serviceOff) ...[
            GlowButton(
              label: 'Turn on location',
              icon: LucideIcons.mapPin,
              height: 54,
              fontSize: 16,
              onPressed: () => Geolocator.openLocationSettings(),
            ),
            const SizedBox(height: 10),
          ],
          if (_problem == _GpsProblem.deniedForever) ...[
            GlowButton(
              label: 'Open app settings',
              icon: LucideIcons.settings,
              iconMotion: IconMotion.spin,
              height: 54,
              fontSize: 16,
              onPressed: () => Geolocator.openAppSettings(),
            ),
            const SizedBox(height: 10),
          ],
          GhostButton(
            label: 'Try again',
            icon: LucideIcons.refreshCw,
            iconMotion: IconMotion.spin,
            onPressed: _startGps,
          ),
        ],
      ),
    );
  }

  Widget _refCard() {
    final c = context.colors;
    final ref = s.refElevation;
    return GlassCard(
      blur: false,
      strong: true,
      onTap: _setReference,
      semanticLabel: ref == null
          ? 'Elevation basis: raw GPS altitude. Tap to set reference'
          : 'Elevation basis: point 1 equals ${ref.toStringAsFixed(3)} metres. Tap to change',
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: c.accent.withAlpha(32),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(LucideIcons.arrowDownToLine, color: c.accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ELEVATION BASIS', style: eyebrow(c.muted)),
                const SizedBox(height: 2),
                Text(
                  ref == null
                      ? 'Raw GPS altitude'
                      : 'Point 1 = ${ref.toStringAsFixed(3)} m (local)',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                      fontFeatures: kTabular),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.scheme.primary.withAlpha(28),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.pencil,
                    size: 15, color: context.scheme.primary),
                const SizedBox(width: 6),
                Text('Set ref',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.scheme.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberBadge(int n, bool lowest) {
    final c = context.colors;
    // White text on these fills is >= 4.5:1.
    final colors = lowest
        ? const [Color(0xFF0369A1), Color(0xFF1D4ED8)]
        : const [Color(0xFF047857), Color(0xFF0E7490)];
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: colors),
        boxShadow: [BoxShadow(color: c.glow, blurRadius: 10)],
      ),
      child:
          Text('$n', style: display(17, color: Colors.white, letterSpacing: 0)),
    );
  }

  // ----- Points tab

  Widget _pointsTab() {
    if (s.points.isEmpty) {
      return _emptyMsg(
        LucideIcons.mapPinned,
        'No points yet',
        'Go to Capture and record the first point on the left bank.',
        action: 'Start capturing',
        onAction: () => _tabs.animateTo(0),
      );
    }
    final d = s.distances();
    var lowIdx = 0;
    for (var i = 1; i < s.points.length; i++) {
      if (s.elevationOf(i) < s.elevationOf(lowIdx)) lowIdx = i;
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 36),
      children: [
        _refCard(),
        const SizedBox(height: 10),
        HintText(
          s.mode == DistanceMode.cumulative
              ? 'Distance: walked path from point 1. Tap a point to edit its note.'
              : 'Distance: along straight line point 1 → last point. Tap a '
                  'point to edit its note.',
          icon: s.mode == DistanceMode.cumulative
              ? LucideIcons.footprints
              : LucideIcons.moveHorizontal,
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < s.points.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FadeSlideIn(
              key: ValueKey('pt-$i-${s.points[i].time.microsecondsSinceEpoch}'),
              index: i,
              child: _pointTile(i, d[i], i == lowIdx && s.points.length > 1),
            ),
          ),
      ],
    );
  }

  Widget _pointTile(int i, double dist, bool lowest) {
    final c = context.colors;
    final p = s.points[i];
    return GlassCard(
      blur: false,
      strong: true,
      onTap: () => _editNote(i),
      semanticLabel: 'Point ${i + 1}, distance ${dist.toStringAsFixed(2)} '
          'metres, elevation ${s.elevationOf(i).toStringAsFixed(2)} metres'
          '${p.note.isEmpty ? '' : ', ${p.note}'}. Tap to edit note',
      padding: const EdgeInsets.fromLTRB(12, 12, 2, 12),
      child: Row(
        children: [
          _numberBadge(i + 1, lowest),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${dist.toStringAsFixed(2)} m'),
                    TextSpan(
                        text: '   El ',
                        style: TextStyle(color: c.muted, fontSize: 14)),
                    TextSpan(
                        text: '${s.elevationOf(i).toStringAsFixed(2)} m',
                        style: TextStyle(color: lowest ? c.water : c.text)),
                  ]),
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                      fontFeatures: kTabular),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (lowest)
                      const InfoChip(
                          icon: LucideIcons.droplet, label: 'Lowest'),
                    InfoChip(
                        icon: LucideIcons.crosshair,
                        label: '±${p.hAcc.toStringAsFixed(1)} m'),
                    if (p.samples > 1)
                      InfoChip(
                          icon: LucideIcons.timer, label: 'avg ${p.samples}'),
                    InfoChip(
                        icon: LucideIcons.clock,
                        label: fmtDateTime(p.time).substring(11)),
                    if (p.note.isNotEmpty)
                      InfoChip(icon: LucideIcons.notebookPen, label: p.note),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Actions for point ${i + 1}',
            icon: Icon(LucideIcons.ellipsisVertical, color: c.text),
            onSelected: (a) {
              if (a == 'note') {
                _editNote(i);
              } else {
                _deletePoint(i);
              }
            },
            itemBuilder: (ctx) => [
              menuItem(ctx, 'note', LucideIcons.notebookPen, 'Edit note'),
              menuItem(ctx, 'delete', LucideIcons.trash2, 'Delete point',
                  danger: true),
            ],
          ),
        ],
      ),
    );
  }

  // ----- Graph tab

  Widget _graphTab() {
    final c = context.colors;
    final prof = s.profile();
    final sum = SectionSummary.of(prof);
    if (sum == null) {
      return _emptyMsg(
        LucideIcons.chartSpline,
        'Not enough points',
        'Capture at least 2 points to see the cross-section graph.',
        action: 'Go to capture',
        onAction: () => _tabs.animateTo(0),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 36),
      children: [
        SegmentedButton<DistanceMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<DistanceMode>(
              value: DistanceMode.cumulative,
              label: Text('Walked path'),
              icon: Icon(LucideIcons.footprints, size: 18),
            ),
            ButtonSegment<DistanceMode>(
              value: DistanceMode.projected,
              label: Text('Straight line'),
              icon: Icon(LucideIcons.moveHorizontal, size: 18),
            ),
          ],
          selected: <DistanceMode>{s.mode},
          onSelectionChanged: (v) {
            setState(() => s.mode = v.first);
            store.save();
          },
        ),
        const SizedBox(height: 8),
        HintText(
          s.mode == DistanceMode.cumulative
              ? 'Distance = sum of distances between consecutive points.'
              : 'Distance measured along the straight line from point 1 to '
                  'the last point (removes zig-zag of walking).',
        ),
        const SizedBox(height: 12),
        GlassCard(
          strong: true,
          padding: EdgeInsets.zero,
          semanticLabel: 'Cross-section graph, ${prof.length} points, '
              'width ${sum.width.toStringAsFixed(1)} metres',
          child: SizedBox(
            height: 380,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey('${s.mode}-${prof.length}'),
                      tween: Tween(begin: 0, end: 1),
                      duration:
                          Motion.of(context, const Duration(milliseconds: 900)),
                      curve: Curves.easeInOutCubic,
                      builder: (context, t, child) => ClipRect(
                        clipper: _RevealClipper(t),
                        child: child,
                      ),
                      child: InteractiveViewer(
                        transformationController: _zoom,
                        minScale: 1,
                        maxScale: 6,
                        child: SizedBox.expand(
                          child: CustomPaint(
                            painter: SectionPainter(
                              profile: prof,
                              style: context.isDark
                                  ? ChartStyle.screenDark
                                  : ChartStyle.screen,
                              label: PointLabel.elevation,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconPill(
                      icon: LucideIcons.scan,
                      tooltip: 'Reset zoom',
                      motion: IconMotion.pop,
                      size: 44,
                      onPressed: () => _zoom.value = Matrix4.identity(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const HintText(
            'Pinch to zoom. Labels = elevation (m). Blue = lowest point.',
            icon: LucideIcons.zoomIn),
        const SizedBox(height: 14),
        _summaryGrid(sum, c),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GlowButton(
                label: 'Export CSV',
                icon: LucideIcons.fileSpreadsheet,
                height: 60,
                fontSize: 16,
                busy: _exporting && !_exportingPng,
                onPressed: _exporting ? null : () => _export(png: false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlowButton(
                label: 'Export PNG',
                icon: LucideIcons.fileImage,
                height: 60,
                fontSize: 16,
                colors: const [Color(0xFF0E7490), Color(0xFF1D4ED8)],
                busy: _exporting && _exportingPng,
                onPressed: _exporting ? null : () => _export(png: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const HintText(
          'Export opens the share menu: save to Drive / Files, or send by '
          'WhatsApp or Gmail. A copy is also kept inside the app.',
          icon: LucideIcons.share2,
        ),
      ],
    );
  }

  Widget _summaryGrid(SectionSummary m, AppColors c) {
    final items = <(IconData, String, String, Color?)>[
      (
        LucideIcons.moveHorizontal,
        'Width',
        '${m.width.toStringAsFixed(2)} m',
        null
      ),
      (
        LucideIcons.droplet,
        'Lowest (bed)',
        '${m.lowest.toStringAsFixed(2)} m',
        c.water
      ),
      (
        LucideIcons.arrowRightFromLine,
        'Left bank',
        '${m.leftBank.toStringAsFixed(2)} m',
        c.accent
      ),
      (
        LucideIcons.arrowLeftFromLine,
        'Right bank',
        '${m.rightBank.toStringAsFixed(2)} m',
        c.accent
      ),
      (
        LucideIcons.trendingDown,
        'Bed below lower bank',
        '${m.depth.toStringAsFixed(2)} m',
        c.water
      ),
      (
        LucideIcons.chartArea,
        'Area below lower bank',
        '${m.area.toStringAsFixed(2)} m²',
        null
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 640 ? 3 : 2;
        final w = (box.maxWidth - 10 * (cols - 1)) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: w,
                child: FadeSlideIn(
                  index: i,
                  child: StatTile(
                    icon: items[i].$1,
                    label: items[i].$2,
                    value: items[i].$3,
                    color: items[i].$4,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Pulsing rings behind the GPS icon while fixes are arriving.
class _Radar extends StatefulWidget {
  const _Radar({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  void _sync() {
    if (widget.active && !Motion.reduced(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Radar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => CustomPaint(
          painter: _RadarPainter(_c.value, widget.active),
          child: child,
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t, this.active);

  final double t;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r * 0.78, Paint()..color = Colors.white.withAlpha(40));
    if (!active) return;
    for (final phase in [0.0, 0.5]) {
      final v = (t + phase) % 1;
      canvas.drawCircle(
        c,
        r * (0.55 + 0.6 * v),
        Paint()
          ..color = Colors.white.withAlpha((120 * (1 - v)).round())
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.t != t || old.active != active;
}

/// Reveals the chart from left to right (bank to bank).
class _RevealClipper extends CustomClipper<Rect> {
  _RevealClipper(this.t);

  final double t;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * t, size.height);

  @override
  bool shouldReclip(covariant _RevealClipper old) => old.t != t;
}
