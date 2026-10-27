import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:tanim/core/theme/app_theme.dart';

/// Frosted round (or capsule, with [label]) button for floating over photos
/// and the camera, like the controls in Apple's Camera and Photos.
class GlassButton extends StatelessWidget {
  const GlassButton({required this.icon, required this.onPressed, required this.tooltip, this.label, super.key});

  final IconData icon;
  final String? label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final content = label == null
        ? Icon(icon, color: Colors.white, size: 20)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 17),
              const SizedBox(width: 6),
              Text(
                label!,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          );
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: GestureDetector(
          onTap: onPressed,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 44,
                constraints: const BoxConstraints(minWidth: 44),
                padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 14),
                alignment: Alignment.center,
                color: Colors.black.withValues(alpha: 0.32),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Apple's inset grouped list section: optional header and footer around a
/// rounded card whose rows are split by inset hairlines.
class GroupedSection extends StatelessWidget {
  const GroupedSection({required this.children, this.header, this.footer, super.key});

  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(fontSize: 13, color: c.secondaryLabel, height: 1.35);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
            child: Text(header!.toUpperCase(), style: small.copyWith(letterSpacing: 0.1)),
          ),
        DecoratedBox(
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Divider(color: c.separator),
                  ),
                child,
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
            child: Text(footer!, style: small),
          ),
      ],
    );
  }
}

/// One row in a [GroupedSection].
class GroupedRow extends StatelessWidget {
  const GroupedRow({required this.title, this.leading, this.subtitle, this.trailing, this.onTap, super.key});

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 17, color: c.label, letterSpacing: -0.3, height: 1.3)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: TextStyle(fontSize: 15, color: c.secondaryLabel, height: 1.35)),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width capsule button. [tinted] is the quieter secondary style.
class PillButton extends StatelessWidget {
  const PillButton({required this.label, required this.onPressed, this.icon, this.tinted = false, super.key});

  final String label;
  final IconData? icon;
  final bool tinted;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null;
    final bg = tinted ? c.accent.withValues(alpha: 0.16) : c.accent;
    final fg = tinted ? c.accent : c.onAccent;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: enabled ? bg : c.fill,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: enabled ? fg : c.tertiaryLabel),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: enabled ? fg : c.tertiaryLabel,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The small handle at the top of a sheet.
class Grabber extends StatelessWidget {
  const Grabber({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 5,
      decoration: BoxDecoration(color: context.colors.tertiaryLabel, borderRadius: BorderRadius.circular(3)),
    ),
  );
}

/// Small rounded chip, e.g. "Blast 2%".
class PillTag extends StatelessWidget {
  const PillTag(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: context.colors.fill, borderRadius: BorderRadius.circular(100)),
    child: Text(text, style: TextStyle(fontSize: 13, color: context.colors.label, letterSpacing: -0.05)),
  );
}
