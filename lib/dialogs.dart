import 'package:flutter/material.dart';

/// Single text-field dialog. Returns the text, or null if cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = '',
  String help = '',
  bool numeric = false,
  String okText = 'SAVE',
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
  });

  final String title;
  final String initial;
  final String label;
  final String help;
  final bool numeric;
  final String okText;

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
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _c,
            autofocus: true,
            style: const TextStyle(fontSize: 20),
            keyboardType: widget.numeric
                ? const TextInputType.numberWithOptions(
                    decimal: true, signed: true)
                : TextInputType.text,
            decoration: InputDecoration(
              labelText: widget.label.isEmpty ? null : widget.label,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          if (widget.help.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(widget.help, style: const TextStyle(color: Colors.black54)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _c.text),
          child: Text(widget.okText),
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
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(fontSize: 16)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828))
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
