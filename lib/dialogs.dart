import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'theme.dart';

/// Round tinted badge shown at the top of dialogs.
class DialogBadge extends StatelessWidget {
  const DialogBadge(this.icon, {super.key, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.scheme.primary;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: c.withAlpha(30),
          shape: BoxShape.circle,
          border: Border.all(color: c.withAlpha(70)),
        ),
        child: Icon(icon, color: c, size: 26),
      ),
    );
  }
}

/// Single text-field dialog. Returns the text, or null if cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = '',
  String help = '',
  bool numeric = false,
  String okText = 'SAVE',
  IconData icon = LucideIcons.pencil,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextDialog(
      title: title,
      initial: initial,
      label: label,
      help: help,
      numeric: numeric,
      okText: okText,
      icon: icon,
    ),
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.label,
    required this.help,
    required this.numeric,
    required this.okText,
    required this.icon,
  });

  final String title;
  final String initial;
  final String label;
  final String help;
  final bool numeric;
  final String okText;
  final IconData icon;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: DialogBadge(widget.icon),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _c,
            autofocus: true,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w500),
            keyboardType: widget.numeric
                ? const TextInputType.numberWithOptions(
                    decimal: true, signed: true)
                : TextInputType.text,
            decoration: InputDecoration(
              labelText: widget.label.isEmpty ? null : widget.label,
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          if (widget.help.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(widget.help,
                style: TextStyle(fontSize: 14, color: context.colors.muted)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _c.text),
          icon: const Icon(LucideIcons.check, size: 18),
          label: Text(widget.okText),
        ),
      ],
    );
  }
}

/// Yes/No confirmation. Returns true only when the user taps [yes].
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String yes = 'YES',
  bool danger = false,
  IconData? icon,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: DialogBadge(
        icon ?? (danger ? LucideIcons.trash2 : LucideIcons.circleHelp),
        color: danger ? ctx.colors.danger : null,
      ),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // White on #B91C1C is 6.4:1, readable in both themes.
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                  foregroundColor: Colors.white)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Parses "100.5" or "100,5". Returns null if not a number.
double? parseNumber(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
