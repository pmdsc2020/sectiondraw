import 'package:flutter/material.dart';

import 'dialogs.dart';
import 'models.dart';
import 'section_screen.dart';
import 'storage.dart';

/// Credit shown in the About box.
const String kCredit =
    'Jitendra Sonawane, Agriculture Engineer, 7720045808';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});

  final SectionStore store;

  void _open(BuildContext context, CrossSection s) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SectionScreen(store: store, section: s),
      ),
    );
  }

  Future<void> _newSection(BuildContext context) async {
    final r = await showDialog<_NewSectionResult>(
      context: context,
      builder: (_) => _NewSectionDialog(suggested: store.suggestName()),
    );
    if (r == null || !context.mounted) return;
    final s = store.addSection(
      name: r.name,
      location: r.location,
      refElevation: r.ref,
    );
    _open(context, s);
  }

  Future<void> _menu(BuildContext context, CrossSection s, String action) async {
    switch (action) {
      case 'rename':
        final v = await askText(context,
            title: 'Rename section', initial: s.name, label: 'Section name');
        if (v != null && v.trim().isNotEmpty) {
          s.name = v.trim();
          store.save();
        }
        break;
      case 'location':
        final v = await askText(context,
            title: 'Village / location',
            initial: s.location,
            label: 'Village, nala, chainage...');
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
          yes: 'DELETE',
          danger: true,
        );
        if (ok) store.deleteSection(s);
        break;
    }
  }

  void _about(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SectionDraw 1.0'),
        content: const SingleChildScrollView(
          child: Text(
            'GPS cross-section survey for nalas, streams and field sections.\n\n'
            'Walk from LEFT bank to RIGHT bank and capture a point every few '
            'metres. All data stays on this phone and works offline.\n\n'
            'Accuracy note: phone GPS height is approximate (often 3-10 m '
            'error in absolute value). Keep the phone steady, wait for good '
            'accuracy, and use averaging. Results are for quick planning; '
            'confirm design levels with an auto level / total station.\n\n'
            'Developed by $kCredit',
            style: TextStyle(fontSize: 15),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = store.sections;
        return Scaffold(
          appBar: AppBar(
            title: const Text('SectionDraw'),
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'About',
                onPressed: () => _about(context),
              ),
            ],
          ),
          body: list.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.terrain, size: 80, color: Color(0xFF8D6E63)),
                        SizedBox(height: 16),
                        Text(
                          'No sections yet',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap NEW SECTION, stand on the left bank and start '
                          'capturing points.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _tile(context, list[i]),
                ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                height: 72,
                child: FilledButton.icon(
                  onPressed: () => _newSection(context),
                  icon: const Icon(Icons.add, size: 32),
                  label: const Text('NEW SECTION',
                      style: TextStyle(fontSize: 22)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, CrossSection s) {
    final sum = SectionSummary.of(s.profile());
    final parts = <String>[
      '${s.points.length} points',
      if (sum != null) 'width ${sum.width.toStringAsFixed(1)} m',
      fmtDate(s.created),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context, s),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Row(
            children: [
              const Icon(Icons.stacked_line_chart,
                  size: 36, color: Color(0xFF5D4037)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    if (s.location.trim().isNotEmpty)
                      Text(s.location,
                          style: const TextStyle(
                              fontSize: 15, color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text(parts.join('  ·  '),
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black54)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 28),
                onSelected: (a) => _menu(context, s, a),
                itemBuilder: (_) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'rename', child: Text('Rename')),
                  PopupMenuItem<String>(
                      value: 'location', child: Text('Edit location')),
                  PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
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
    final name = _name.text.trim().isEmpty ? widget.suggested : _name.text.trim();
    Navigator.pop(context, _NewSectionResult(name, _loc.text.trim(), ref));
  }

  @override
  Widget build(BuildContext context) {
    const big = TextStyle(fontSize: 19);
    return AlertDialog(
      title: const Text('New section'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              style: big,
              decoration: const InputDecoration(
                labelText: 'Section name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _loc,
              style: big,
              decoration: const InputDecoration(
                labelText: 'Village / nala / chainage (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ref,
              style: big,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: 'Reference elevation of first point (m)',
                hintText: 'e.g. 100.000  (optional)',
                helperText: 'Leave empty to use GPS altitude',
                errorText: _refError,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        FilledButton(onPressed: _create, child: const Text('CREATE')),
      ],
    );
  }
}
