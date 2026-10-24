import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sectiondraw/main.dart';
import 'package:sectiondraw/models.dart';
import 'package:sectiondraw/storage.dart';
import 'package:sectiondraw/theme.dart';
import 'package:sectiondraw/ui/logo.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

SectionStore storeWith(List<String> names) {
  final store = SectionStore();
  for (final n in names) {
    final s = store.addSection(name: n, location: '$n village');
    for (var i = 0; i < 4; i++) {
      s.points.add(SectionPoint(
        lat: 21.37,
        lon: 74.24 + i * 0.00003,
        gpsAlt: 200 - (i == 2 ? 2 : 0),
        hAcc: 3,
        vAcc: 4,
        samples: 1,
        time: DateTime(2026, 10, 24, 10, i),
      ));
    }
  }
  return store;
}

void main() {
  group('colour contrast (WCAG AA)', () {
    for (final (name, c) in [
      ('light', AppColors.light),
      ('dark', AppColors.dark),
    ]) {
      test('$name text and muted text on backgrounds', () {
        for (final bg in [
          c.bgTop,
          c.bgBottom,
          Color.alphaBlend(c.glassStrong, c.bgTop)
        ]) {
          expect(contrast(c.text, bg), greaterThanOrEqualTo(7));
          expect(contrast(c.muted, bg), greaterThanOrEqualTo(4.5));
        }
      });
      test('$name white text on GPS status fills', () {
        for (final f in [c.good, c.fair, c.poor, c.idle]) {
          expect(contrast(Colors.white, f), greaterThanOrEqualTo(4.5));
        }
      });
    }
    test('primary button text', () {
      for (final b in [Brightness.light, Brightness.dark]) {
        final s = buildTheme(b).colorScheme;
        expect(contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
      }
    });
  });

  testWidgets('splash plays logo animation then shows home', (tester) async {
    await tester.pumpWidget(SectionDrawApp(store: storeWith(['Nala A'])));
    expect(find.byType(AnimatedLogo), findsOneWidget);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Nala A'), findsOneWidget);
    expect(find.text('New section'), findsOneWidget);
  });

  testWidgets('theme toggle cycles system -> light -> dark', (tester) async {
    final store = storeWith(['Nala A']);
    await tester.pumpWidget(SectionDrawApp(store: store, splash: false));
    await tester.pump(const Duration(seconds: 1));
    expect(store.themeMode, ThemeMode.system);
    await tester.tap(find.bySemanticsLabel(RegExp('^Theme: System')));
    await tester.pump(const Duration(seconds: 1));
    expect(store.themeMode, ThemeMode.light);
    await tester.tap(find.bySemanticsLabel(RegExp('^Theme: Light')));
    await tester.pump(const Duration(seconds: 1));
    expect(store.themeMode, ThemeMode.dark);
    expect(store.toJson()['theme'], 'dark');
  });

  testWidgets('search filters the section list', (tester) async {
    await tester.pumpWidget(SectionDrawApp(
        store: storeWith(['Nala A', 'Stream B', 'Field C']), splash: false));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Stream B'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'nala');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Nala A'), findsOneWidget);
    expect(find.text('Stream B'), findsNothing);
    expect(find.text('1 of 3 shown'), findsOneWidget);
  });

  testWidgets('new section dialog creates and opens a section', (tester) async {
    final store = SectionStore();
    await tester.pumpWidget(SectionDrawApp(store: store, splash: false));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('No sections yet'), findsOneWidget);
    await tester.tap(find.text('New section'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Create & start'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(store.sections, hasLength(1));
    expect(store.sections.first.name, 'Section 1');
    // The section screen is open on the Capture tab.
    expect(find.text('Capture'), findsOneWidget);
    expect(
        find.text('GPS ACCURACY').evaluate().length +
            find.text('Try again').evaluate().length,
        greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
