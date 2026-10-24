import 'package:flutter/material.dart';

/// Shared motion tokens so every micro-animation feels like one system.
class Motion {
  static const fast = Duration(milliseconds: 140);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 520);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve spring = Curves.easeOutBack;

  /// True when the user asked the OS to reduce or remove animations.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or zero when animations are reduced.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}

/// Fades and slides its child in once, after [index] * [stagger].
/// Used for list entries so screens build up gracefully.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.stagger = const Duration(milliseconds: 55),
    this.offset = const Offset(0, 0.08),
  });

  final Widget child;
  final int index;
  final Duration stagger;
  final Offset offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  late Animation<double> _t = _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (Motion.reduced(context)) {
      _c.value = 1;
      return;
    }
    // The stagger delay is the start of the curve's interval, so no timers
    // outlive the widget. Capped so long lists do not wait forever.
    final delay = widget.stagger * widget.index.clamp(0, 8);
    final total = delay + Motion.slow;
    _c.duration = total;
    _t = CurvedAnimation(
      parent: _c,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1,
          curve: Motion.emphasized),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _t,
      child: SlideTransition(
        position:
            Tween<Offset>(begin: widget.offset, end: Offset.zero).animate(_t),
        child: widget.child,
      ),
    );
  }
}
