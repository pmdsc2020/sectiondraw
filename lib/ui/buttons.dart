import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'motion.dart';

/// How a [MotionIcon] reacts when it is triggered.
enum IconMotion { pop, spin, wiggle, bounce, nudge }

/// A Lucide (or any) icon that plays a short motion every time [trigger]
/// changes to true - on hover, press or when a value updates.
class MotionIcon extends StatefulWidget {
  const MotionIcon(
    this.icon, {
    super.key,
    this.trigger = false,
    this.motion = IconMotion.pop,
    this.size = 22,
    this.color,
    this.semanticLabel,
  });

  final IconData icon;
  final bool trigger;
  final IconMotion motion;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  State<MotionIcon> createState() => _MotionIconState();
}

class _MotionIconState extends State<MotionIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void didUpdateWidget(covariant MotionIcon old) {
    super.didUpdateWidget(old);
    if (widget.trigger && !old.trigger && !Motion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(widget.icon,
        size: widget.size,
        color: widget.color,
        semanticLabel: widget.semanticLabel);
    return AnimatedBuilder(
      animation: _c,
      child: icon,
      builder: (context, child) {
        final t = _c.value;
        // Decaying oscillation 0 -> 0 used by wiggle / bounce / nudge.
        final wave = math.sin(t * math.pi * 3) * (1 - t);
        switch (widget.motion) {
          case IconMotion.pop:
            final s = 1 + 0.28 * math.sin(t * math.pi) * (1 - t * 0.4);
            return Transform.scale(scale: s, child: child);
          case IconMotion.spin:
            return Transform.rotate(
                angle: Curves.easeOutBack.transform(t) * math.pi * 2 / 4,
                child: child);
          case IconMotion.wiggle:
            return Transform.rotate(angle: wave * 0.35, child: child);
          case IconMotion.bounce:
            return Transform.translate(
                offset: Offset(0, -wave.abs() * widget.size * 0.35),
                child: child);
          case IconMotion.nudge:
            return Transform.translate(
                offset: Offset(wave.abs() * widget.size * 0.3, 0),
                child: child);
        }
      },
    );
  }
}

/// Tracks hover / press state for the button widgets below.
mixin _InteractiveState<T extends StatefulWidget> on State<T> {
  bool hover = false;
  bool pressed = false;
  bool focused = false;

  bool get active => hover || pressed || focused;

  Widget interactive({
    required bool enabled,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onShowHoverHighlight: (v) => setState(() => hover = v),
      onShowFocusHighlight: (v) => setState(() => focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          if (enabled) onTap?.call();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => pressed = true) : null,
        onTapUp: (_) => setState(() => pressed = false),
        onTapCancel: () => setState(() => pressed = false),
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                onTap?.call();
              }
            : null,
        child: child,
      ),
    );
  }
}

/// Primary call-to-action: gradient fill, soft glow, light sweep on hover,
/// press-to-sink, and an optional circular [progress] ring for timed work.
class GlowButton extends StatefulWidget {
  const GlowButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.height = 60,
    this.colors,
    this.busy = false,
    this.progress,
    this.iconMotion = IconMotion.pop,
    this.fontSize = 17,
    this.semanticLabel,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final double height;

  /// Gradient override (defaults to the brand gradient).
  final List<Color>? colors;
  final bool busy;

  /// 0..1 shows a progress ring in place of the icon.
  final double? progress;
  final IconMotion iconMotion;
  final double fontSize;
  final String? semanticLabel;

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton>
    with SingleTickerProviderStateMixin, _InteractiveState<GlowButton> {
  late final AnimationController _sweep = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  bool get _enabled => widget.onPressed != null && !widget.busy;

  @override
  void setState(VoidCallback fn) {
    final was = hover;
    super.setState(fn);
    if (hover && !was && !Motion.reduced(context)) _sweep.forward(from: 0);
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // White text on these gradients is >= 4.5:1 in both themes.
    final colors =
        widget.colors ?? const [Color(0xFF047857), Color(0xFF0E7490)];
    final d = Motion.of(context, Motion.fast);
    final enabled = _enabled;
    const fg = Colors.white;
    final br = BorderRadius.circular(widget.height * 0.32);

    Widget lead;
    if (widget.progress != null) {
      lead = SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          value: widget.progress,
          strokeWidth: 3,
          color: fg,
          backgroundColor: fg.withAlpha(60),
        ),
      );
    } else if (widget.busy) {
      lead = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
      );
    } else {
      lead = MotionIcon(widget.icon,
          trigger: active,
          motion: widget.iconMotion,
          color: fg,
          size: widget.fontSize + 9);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      child: interactive(
        enabled: enabled,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: pressed ? 0.97 : 1,
          duration: d,
          curve: Motion.emphasized,
          child: AnimatedOpacity(
            opacity: widget.onPressed == null ? 0.45 : 1,
            duration: d,
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.medium),
              curve: Motion.emphasized,
              constraints: BoxConstraints(minHeight: widget.height),
              decoration: BoxDecoration(
                borderRadius: br,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
                border: focused
                    ? Border.all(color: context.scheme.onSurface, width: 3)
                    : Border.all(color: Colors.white.withAlpha(40)),
                boxShadow: [
                  BoxShadow(
                    color: colors.last.withAlpha(hover ? 140 : 90),
                    blurRadius: hover ? 30 : 18,
                    spreadRadius: hover ? 1 : 0,
                    offset: Offset(0, pressed ? 3 : 8),
                  ),
                  BoxShadow(color: c.glow, blurRadius: 2),
                ],
              ),
              child: ClipRRect(
                borderRadius: br,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Light sweep across the button on hover.
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _sweep,
                        builder: (context, _) => _sweep.isAnimating
                            ? FractionalTranslation(
                                translation: Offset(-1 + _sweep.value * 2.2, 0),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [
                                      Colors.white.withAlpha(0),
                                      Colors.white.withAlpha(60),
                                      Colors.white.withAlpha(0),
                                    ]),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          lead,
                          const SizedBox(width: 12),
                          Flexible(
                            child: AnimatedSwitcher(
                              duration: Motion.of(context, Motion.medium),
                              transitionBuilder: (child, a) => FadeTransition(
                                opacity: a,
                                child: SlideTransition(
                                  position: Tween(
                                          begin: const Offset(0, 0.4),
                                          end: Offset.zero)
                                      .animate(a),
                                  child: child,
                                ),
                              ),
                              child: Text(
                                widget.label,
                                key: ValueKey(widget.label),
                                textAlign: TextAlign.center,
                                style: display(widget.fontSize,
                                    color: fg, letterSpacing: 0.2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary button: glass fill, hairline border, icon motion on hover.
class GhostButton extends StatefulWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.height = 52,
    this.color,
    this.iconMotion = IconMotion.pop,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final double height;

  /// Foreground colour; defaults to the theme text colour.
  final Color? color;
  final IconMotion iconMotion;

  @override
  State<GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<GhostButton>
    with _InteractiveState<GhostButton> {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null;
    final fg = widget.color ?? c.text;
    final d = Motion.of(context, Motion.fast);
    final br = BorderRadius.circular(16);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: interactive(
        enabled: enabled,
        onTap: widget.onPressed,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.42,
          duration: d,
          child: AnimatedScale(
            scale: pressed ? 0.96 : 1,
            duration: d,
            child: AnimatedContainer(
              duration: d,
              constraints: BoxConstraints(minHeight: widget.height),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: br,
                color: hover && enabled
                    ? Color.alphaBlend(fg.withAlpha(22), c.glassStrong)
                    : c.glass,
                border: Border.all(
                  color: focused
                      ? context.scheme.primary
                      : (hover && enabled ? fg.withAlpha(110) : c.glassBorder),
                  width: focused ? 2.5 : 1.2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MotionIcon(widget.icon,
                      trigger: active,
                      motion: widget.iconMotion,
                      color: fg,
                      size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: kBodyFont,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round glass icon button with tooltip, motion and a 48 dp tap target.
class IconPill extends StatefulWidget {
  const IconPill({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.motion = IconMotion.pop,
    this.size = 48,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final IconMotion motion;
  final double size;
  final Color? color;

  @override
  State<IconPill> createState() => _IconPillState();
}

class _IconPillState extends State<IconPill> with _InteractiveState<IconPill> {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null;
    final d = Motion.of(context, Motion.fast);
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        excludeSemantics: true,
        child: interactive(
          enabled: enabled,
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: pressed ? 0.9 : (hover ? 1.06 : 1),
            duration: d,
            curve: Motion.spring,
            child: AnimatedContainer(
              duration: d,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hover ? c.glassStrong : c.glass,
                border: Border.all(
                  color: focused ? context.scheme.primary : c.glassBorder,
                  width: focused ? 2.5 : 1,
                ),
              ),
              child: Center(
                child: MotionIcon(widget.icon,
                    trigger: active,
                    motion: widget.motion,
                    size: 21,
                    color: widget.color ?? c.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
