import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'dialogs.dart';
import 'models.dart';
import 'section_screen.dart';
import 'storage.dart';
import 'theme.dart';
import 'ui/buttons.dart';
import 'ui/glass.dart';
import 'ui/logo.dart';
import 'ui/motion.dart';
import 'ui/sparkline.dart';
import 'ui/theme_toggle.dart';
import 'ui/widgets.dart';

/// Credit shown in the About box.
const String kCredit = 'Jitendra Sonawane, Agriculture Engineer, 7720045808';

enum _Sort { newest, name, points }

/// Builds a popup-menu row with a Lucide icon.
PopupMenuItem<String> menuItem(
    BuildContext context, String value, IconData icon, String label,
    {bool danger = false}) {
  final color = danger ? context.colors.danger : context.colors.text;
  return PopupMenuItem<String>(
    value: value,
    height: 48,
    child: Row(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ],
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final SectionStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  _Sort _sort = _Sort.newest;

  SectionStore get store => widget.store;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(CrossSection s) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SectionScreen(store: store, section: s),
      ),
    );
  }

  Future<void> _newSection() async {
    final r = await showDialog<_NewSectionResult>(
      context: context,
      builder: (_) => _NewSectionDialog(suggested: store.suggestName()),
    );
    if (r == null || !mounted) return;
    final s = store.addSection(
      name: r.name,
      location: r.location,
      refElevation: r.ref,
    );
    _open(s);
  }

  Future<void> _menu(CrossSection s, String action) async {
    switch (action) {
      case 'open':
        _open(s);
        break;
      case 'rename':
        final v = await askText(context,
            title: 'Rename section', initial: s.name, label: 'Section name');
        if (v != null && v.trim().isNotEmpty) {
          s.name = v.trim();
          store.save();
        }
        break;
      case 'location':
        if (!mounted) return;
        final v = await askText(context,
            title: 'Village / location',
            initial: s.location,
            label: 'Village, nala, chainage...',
            icon: LucideIcons.mapPin);
        if (v != null) {
          s.location = v.trim();
          store.save();
        }
        break;
      case 'delete':
        final ok = await confirm(
          context,
          title: 'Delete section?',
          message:
              '"${s.name}" and its ${s.points.length} points will be deleted '
              'permanently. Export CSV first if you need the data.',
          yes: 'Delete',
          danger: true,
        );
        if (ok) store.deleteSection(s);
        break;
    }
  }

  void _about() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const LogoMark(size: 64),
        title: const Text('SectionDraw 1.0'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'GPS cross-section survey for nalas, streams and field '
                'sections.',
              ),
              const SizedBox(height: 14),
              const HintText(
                'Walk from LEFT bank to RIGHT bank and capture a point every '
                'few metres. All data stays on this phone and works offline.',
                icon: LucideIcons.footprints,
              ),
              const SizedBox(height: 10),
              const HintText(
                'Phone GPS height is approximate (often 3-10 m error in '
                'absolute value). Keep the phone steady, wait for good '
                'accuracy, and use averaging. Results are for quick planning; '
                'confirm design levels with an auto level / total station.',
                icon: LucideIcons.triangleAlert,
              ),
              const SizedBox(height: 16),
              Text('Developed by $kCredit',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ctx.colors.text)),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  List<CrossSection> _visible() {
    final q = _query.trim().toLowerCase();
    final list = [
      for (final s in store.sections)
        if (q.isEmpty ||
            s.name.toLowerCase().contains(q) ||
            s.location.toLowerCase().contains(q))
          s,
    ];
    switch (_sort) {
      case _Sort.newest:
        list.sort((a, b) => b.created.compareTo(a.created));
      case _Sort.name:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _Sort.points:
        list.sort((a, b) => b.points.length.compareTo(a.points.length));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final all = store.sections;
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: AuroraBackground(
            child: SafeArea(
              bottom: false,
              child: all.isEmpty
                  ? Column(
                      children: [
                        _header(),
                        Expanded(
                          child: EmptyState(
                            icon: LucideIcons.mountain,
                            art: const AnimatedLogo(size: 104, pulse: true),
                            title: 'No sections yet',
                            message: 'Create a section, stand on the left bank '
                                'and start capturing GPS points.',
                          ),
                        ),
                      ],
                    )
                  : _content(all),
            ),
          ),
          bottomNavigationBar: _newButton(),
        );
      },
    );
  }

  Widget _newButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SizedBox(
              width: double.infinity,
              child: GlowButton(
                label: 'New section',
                icon: LucideIcons.plus,
                iconMotion: IconMotion.spin,
                height: 64,
                fontSize: 19,
                onPressed: _newSection,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 6),
      child: Row(
        children: [
          const LogoMark(size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('SectionDraw', style: display(24, color: c.text)),
                ),
                Text('GPS cross-sections · offline',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.muted)),
              ],
            ),
          ),
          ThemeToggle(store: store),
          const SizedBox(width: 8),
          IconPill(
            icon: LucideIcons.info,
            tooltip: 'About SectionDraw',
            motion: IconMotion.wiggle,
            onPressed: _about,
          ),
        ],
      ),
    );
  }

  Widget _content(List<CrossSection> all) {
    final list = _visible();
    var points = 0;
    var metres = 0.0;
    for (final s in all) {
      points += s.points.length;
      final sum = SectionSummary.of(s.profile());
      if (sum != null) metres += sum.width;
    }

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 760;
      final pad = wide ? (box.maxWidth - 1100).clamp(24.0, 9999.0) / 2 : 16.0;
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header()),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 10, pad, 0),
            sliver: SliverToBoxAdapter(
              child: FadeSlideIn(
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: StatTile(
                          icon: LucideIcons.layers,
                          label: 'Sections',
                          value: '${all.length}',
                          blur: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          icon: LucideIcons.mapPinned,
                          label: 'Points',
                          value: '$points',
                          color: context.colors.water,
                          blur: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          icon: LucideIcons.ruler,
                          label: 'Surveyed',
                          value: '${metres.toStringAsFixed(0)} m',
                          color: context.colors.accent,
                          blur: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, 4),
            sliver: SliverToBoxAdapter(child: _searchBar()),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 8),
            sliver: SliverToBoxAdapter(child: _sortRow(list.length)),
          ),
          if (list.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Column(
                  children: [
                    Icon(LucideIcons.searchX,
                        size: 40, color: context.colors.muted),
                    const SizedBox(height: 10),
                    Text('No section matches "$_query"',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16, color: context.colors.muted)),
                  ],
                ),
              ),
            )
          else if (wide)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 120),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(builder: (context, c) {
                  final w = (c.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (var i = 0; i < list.length; i++)
                        SizedBox(
                          width: w,
                          child: FadeSlideIn(
                              key: ValueKey(list[i].id),
                              index: i,
                              child: _card(list[i])),
                        ),
                    ],
                  );
                }),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 120),
              sliver: SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => FadeSlideIn(
                  key: ValueKey(list[i].id),
                  index: i,
                  child: _card(list[i]),
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _searchBar() {
    final c = context.colors;
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 16.5),
      decoration: InputDecoration(
        hintText: 'Search name or village',
        prefixIcon: Icon(LucideIcons.search, size: 20, color: c.muted),
        suffixIcon: AnimatedSwitcher(
          duration: Motion.of(context, Motion.fast),
          child: _query.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  key: const ValueKey('clear'),
                  tooltip: 'Clear search',
                  icon: Icon(LucideIcons.x, size: 20, color: c.text),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
        ),
      ),
    );
  }

  Widget _sortRow(int shown) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (sort, label, icon) in const [
                (_Sort.newest, 'Newest', LucideIcons.calendar),
                (_Sort.name, 'Name', LucideIcons.arrowDownAZ),
                (_Sort.points, 'Most points', LucideIcons.mapPinned),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SelectChip(
                    label: label,
                    icon: icon,
                    selected: _sort == sort,
                    onTap: () => setState(() => _sort = sort),
                  ),
                ),
            ],
          ),
        ),
        if (_query.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('$shown of ${store.sections.length} shown',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: c.muted)),
        ],
      ],
    );
  }

  Widget _card(CrossSection s) {
    final c = context.colors;
    final prof = s.profile();
    final sum = SectionSummary.of(prof);
    return GlassCard(
      blur: false,
      strong: true,
      onTap: () => _open(s),
      onLongPress: () => _menu(s, 'rename'),
      semanticLabel: 'Open ${s.name}, ${s.points.length} points',
      padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
      child: Row(
        children: [
          ProfileSparkline(profile: prof),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: display(19,
                        weight: FontWeight.w600,
                        color: c.text,
                        letterSpacing: -0.2)),
                if (s.location.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(LucideIcons.mapPin, size: 14, color: c.muted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(s.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: c.muted)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    InfoChip(
                        icon: LucideIcons.circleDot,
                        label: '${s.points.length} pts'),
                    if (sum != null)
                      InfoChip(
                          icon: LucideIcons.moveHorizontal,
                          label: '${sum.width.toStringAsFixed(1)} m'),
                    InfoChip(
                        icon: LucideIcons.calendar, label: fmtDate(s.created)),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions for ${s.name}',
            icon: Icon(LucideIcons.ellipsisVertical, color: c.text),
            onSelected: (a) => _menu(s, a),
            itemBuilder: (ctx) => [
              menuItem(ctx, 'open', LucideIcons.arrowRight, 'Open'),
              menuItem(ctx, 'rename', LucideIcons.pencil, 'Rename'),
              menuItem(ctx, 'location', LucideIcons.mapPin, 'Edit location'),
              const PopupMenuDivider(),
              menuItem(ctx, 'delete', LucideIcons.trash2, 'Delete',
                  danger: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _NewSectionResult {
  const _NewSectionResult(this.name, this.location, this.ref);
  final String name;
  final String location;
  final double? ref;
}

class _NewSectionDialog extends StatefulWidget {
  const _NewSectionDialog({required this.suggested});
  final String suggested;

  @override
  State<_NewSectionDialog> createState() => _NewSectionDialogState();
}

class _NewSectionDialogState extends State<_NewSectionDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.suggested);
  final TextEditingController _loc = TextEditingController();
  final TextEditingController _ref = TextEditingController();
  String? _refError;

  @override
  void dispose() {
    _name.dispose();
    _loc.dispose();
    _ref.dispose();
    super.dispose();
  }

  void _create() {
    final refTxt = _ref.text.trim();
    double? ref;
    if (refTxt.isNotEmpty) {
      ref = parseNumber(refTxt);
      if (ref == null) {
        setState(() => _refError = 'Enter a number, e.g. 100');
        return;
      }
    }
    final name =
        _name.text.trim().isEmpty ? widget.suggested : _name.text.trim();
    Navigator.pop(context, _NewSectionResult(name, _loc.text.trim(), ref));
  }

  @override
  Widget build(BuildContext context) {
    const big = TextStyle(fontSize: 17.5, fontWeight: FontWeight.w500);
    final muted = context.colors.muted;
    return AlertDialog(
      icon: const DialogBadge(LucideIcons.squarePlus),
      title: const Text('New section'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              style: big,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Section name',
                prefixIcon: Icon(LucideIcons.tag, size: 20, color: muted),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _loc,
              style: big,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Village / nala (optional)',
                prefixIcon: Icon(LucideIcons.mapPin, size: 20, color: muted),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ref,
              style: big,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              onSubmitted: (_) => _create(),
              decoration: InputDecoration(
                labelText: 'Point 1 elevation (m)',
                hintText: 'e.g. 100.000  (optional)',
                helperText: 'Optional local datum. Empty = GPS altitude',
                errorText: _refError,
                prefixIcon:
                    Icon(LucideIcons.arrowDownToLine, size: 20, color: muted),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _create,
          icon: const Icon(LucideIcons.arrowRight, size: 18),
          label: const Text('Create & start'),
        ),
      ],
    );
  }
}
