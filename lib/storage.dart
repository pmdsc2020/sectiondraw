import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Keeps all sections and settings in one JSON file on the phone.
/// Works fully offline.
class SectionStore extends ChangeNotifier {
  final List<CrossSection> sections = <CrossSection>[];

  /// Seconds of GPS readings averaged for each captured point (0 = single fix).
  int avgSeconds = 5;

  /// Light, dark or follow the phone setting.
  ThemeMode themeMode = ThemeMode.system;

  File? _file;
  bool _saving = false;
  bool _saveAgain = false;

  Future<void> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/sectiondraw_data.json');
      _file = f;
      if (!await f.exists()) return;
      final txt = await f.readAsString();
      try {
        final j = jsonDecode(txt) as Map<String, dynamic>;
        avgSeconds = (j['avgSeconds'] as num? ?? 5).toInt();
        if (!const [0, 5, 10].contains(avgSeconds)) avgSeconds = 5;
        themeMode = ThemeMode.values.firstWhere(
          (m) => m.name == j['theme'],
          orElse: () => ThemeMode.system,
        );
        sections
          ..clear()
          ..addAll([
            for (final s in (j['sections'] as List? ?? const []))
              CrossSection.fromJson(Map<String, dynamic>.from(s as Map)),
          ]);
        _sort();
      } catch (e) {
        // Never overwrite data we could not read: keep a copy aside.
        final stamp = DateTime.now().millisecondsSinceEpoch;
        await f.copy('${f.path}.unreadable-$stamp');
        debugPrint('SectionDraw: could not parse data file: $e');
      }
    } catch (e) {
      debugPrint('SectionDraw: storage error: $e');
    }
  }

  void _sort() => sections.sort((a, b) => b.created.compareTo(a.created));

  Map<String, dynamic> toJson() => {
        'app': 'SectionDraw',
        'version': 1,
        'avgSeconds': avgSeconds,
        'theme': themeMode.name,
        'sections': [for (final s in sections) s.toJson()],
      };

  /// Notify listeners and write everything to disk (atomic replace).
  Future<void> save() async {
    notifyListeners();
    final f = _file;
    if (f == null) return;
    if (_saving) {
      _saveAgain = true;
      return;
    }
    _saving = true;
    try {
      do {
        _saveAgain = false;
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(jsonEncode(toJson()), flush: true);
        await tmp.rename(f.path);
      } while (_saveAgain);
    } catch (e) {
      debugPrint('SectionDraw: save failed: $e');
    } finally {
      _saving = false;
    }
  }

  CrossSection addSection({
    required String name,
    String location = '',
    double? refElevation,
  }) {
    final s = CrossSection(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      location: location,
      created: DateTime.now(),
      refElevation: refElevation,
    );
    sections.add(s);
    _sort();
    save();
    return s;
  }

  void deleteSection(CrossSection s) {
    sections.removeWhere((x) => x.id == s.id);
    save();
  }

  /// System -> Light -> Dark -> System.
  void cycleTheme() {
    themeMode = switch (themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    save();
  }

  String suggestName() {
    var n = sections.length + 1;
    while (sections.any((s) => s.name == 'Section $n')) {
      n++;
    }
    return 'Section $n';
  }
}
