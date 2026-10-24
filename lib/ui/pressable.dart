import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'motion.dart';

/// Makes any surface clickable with consistent micro-interactions:
/// lifts on hover, sinks on press, shows a focus ring for keyboard users,
/// gives haptic feedback and exposes button semantics to screen readers.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.pressedScale = 0.97,
    this.hoverLift = 3,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final BorderRadius borderRadius;
  final double pressedScale;
  final double hoverLift;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _tap() {
    if (widget.haptic) HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Motion.fast);
    final scale = _pressed ? widget.pressedScale : 1.0;
    final lift = (_hover && !_pressed) ? -widget.hoverLift : 0.0;

    return Semantics(
      button: _enabled,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: _enabled,
        mouseCursor:
            _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (widget.onTap != null) _tap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap == null ? null : _tap,
          onLongPress: widget.onLongPress == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  widget.onLongPress!();
                },
          child: AnimatedContainer(
            duration: d,
            curve: Motion.emphasized,
            transform: Matrix4.translationValues(0, lift, 0),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: _hover && _enabled
                  ? [
                      BoxShadow(
                        color: context.colors.glow,
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : const [],
            ),
            foregroundDecoration: _focused
                ? BoxDecoration(
                    borderRadius: widget.borderRadius,
                    border: Border.all(color: context.scheme.primary, width: 3),
                  )
                : null,
            child: AnimatedScale(
              scale: scale,
              duration: d,
              curve: Motion.emphasized,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
