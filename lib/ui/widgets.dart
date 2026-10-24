import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme.dart';
import 'buttons.dart';
import 'glass.dart';
import 'motion.dart';
import 'pressable.dart';

/// Text that rolls up to its new value whenever [value] changes.
class RollingText extends StatelessWidget {
  const RollingText(this.value, {super.key, required this.style});

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      switchInCurve: Motion.emphasized,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, a) {
        final incoming = child.key == ValueKey(value);
        return ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, incoming ? 0.6 : -0.6),
              end: Offset.zero,
            ).animate(a),
            child: FadeTransition(opacity: a, child: child),
          ),
        );
      },
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, if (current != null) current],
      ),
      child: Text(value,
          key: ValueKey(value),
          maxLines: 1,
          style: style.copyWith(fontFeatures: kTabular)),
    );
  }
}

/// Icon + caption + big value. Tappable when [onTap] is set.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
    this.onTap,
    this.blur = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  final VoidCallback? onTap;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = color ?? context.scheme.primary;
    return GlassCard(
      blur: blur,
      strong: true,
      radius: 18,
      onTap: onTap,
      semanticLabel: '$label: $value',
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: accent.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: accent),
            ),
            const SizedBox(height: 10),
            Text(
              label.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: eyebrow(c.muted),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: RollingText(value,
                  style: display(22, color: c.text, letterSpacing: -0.3)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded label with an icon, e.g. "12 points".
class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.text.withAlpha(14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.muted),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                  fontFeatures: kTabular)),
        ],
      ),
    );
  }
}

/// Toggle chip with an animated check mark (used for quick notes, filters).
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.scheme;
    final d = Motion.of(context, Motion.medium);
    return Semantics(
      selected: selected,
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        hoverLift: 2,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: d,
          curve: Motion.emphasized,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? s.primary : c.glassStrong,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? s.primary : c.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: d,
                curve: Motion.emphasized,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(LucideIcons.check,
                            size: 16, color: s.onPrimary),
                      )
                    : (icon == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(icon, size: 16, color: c.muted),
                          )),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? s.onPrimary : c.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Muted helper line with a leading icon.
class HintText extends StatelessWidget {
  const HintText(this.text, {super.key, this.icon = LucideIcons.info});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: c.muted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted)),
        ),
      ],
    );
  }
}

/// Friendly empty screen with a gently floating icon and an optional action.
class EmptyState extends StatefulWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.art,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  /// Replaces the floating icon (e.g. the animated logo).
  final Widget? art;

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Motion.reduced(context) && !_float.isAnimating) {
      _float.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.scheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: FadeSlideIn(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _float,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(
                        0, -8 * Curves.easeInOut.transform(_float.value)),
                    child: child,
                  ),
                  child: widget.art ??
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              s.primary.withAlpha(50),
                              s.secondary.withAlpha(30),
                            ],
                          ),
                          border: Border.all(color: c.glassBorder),
                        ),
                        child: Icon(widget.icon, size: 42, color: s.primary),
                      ),
                ),
                const SizedBox(height: 22),
                Text(widget.title,
                    textAlign: TextAlign.center,
                    style: display(24, color: c.text)),
                const SizedBox(height: 8),
                Text(widget.message,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 16, height: 1.45, color: c.muted)),
                if (widget.onAction != null && widget.actionLabel != null) ...[
                  const SizedBox(height: 22),
                  GlowButton(
                    label: widget.actionLabel!,
                    icon: widget.actionIcon ?? LucideIcons.plus,
                    iconMotion: IconMotion.spin,
                    onPressed: widget.onAction,
                    height: 54,
                    fontSize: 16,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
