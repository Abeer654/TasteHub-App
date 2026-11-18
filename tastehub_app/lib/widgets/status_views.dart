// ============================================================
//  status_views.dart - shared loading, empty and error states
// ============================================================

import 'package:flutter/material.dart';

import '../theme.dart';
import 'dish_card.dart';
import 'recipe_list_card.dart';

class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionIcon = Icons.refresh_rounded,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final accent = isError ? colors.error : colors.accent;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
          decoration: BoxDecoration(
            color: colors.card.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isError
                  ? colors.error.withValues(alpha: 0.25)
                  : colors.line,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 27),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.muted),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: onAction,
                      icon: Icon(actionIcon, size: 18),
                      label: Text(actionLabel!),
                    ),
                    if (secondaryActionLabel != null &&
                        onSecondaryAction != null)
                      OutlinedButton(
                        onPressed: onSecondaryAction,
                        child: Text(secondaryActionLabel!),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message = 'Loading recipes...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    // Kept for short, unstructured waits; the list screens show the
    // card skeletons instead (G-06 4).
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
//  G-06 (4): skeleton cards
//
//  Loading shows placeholders shaped like the real cards instead of a
//  spinner, so nothing jumps when the data lands. The blocks breathe with
//  a slow pulse; they are pure decoration, so they carry no semantics.
// ------------------------------------------------------------

/// A single pulsing grey block. Null [width]/[height] means "take what
/// the parent gives", which is what the flexible text bars want.
class _PulseBox extends StatefulWidget {
  const _PulseBox({this.width, this.height, this.radius = 6});

  final double? width;
  final double? height;
  final double radius;

  @override
  State<_PulseBox> createState() => _PulseBoxState();
}

class _PulseBoxState extends State<_PulseBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(colors.field, colors.line, _controller.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: child,
      ),
    );
  }
}

/// Loading stand-in for [DishCard]: same 112dp height, the same 96dp
/// square photo inset 8dp on the top/bottom, three bars on the right.
class DishCardSkeleton extends StatelessWidget {
  const DishCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      height: DishCard.height,
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: TasteHubRadii.cardBorder,
        border: Border.all(color: colors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: const _PulseBox(width: DishCard.photoSize, radius: 12),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PulseBox(width: 120, height: 16),
                const SizedBox(height: 9),
                _PulseBox(width: 150, height: 12),
                const SizedBox(height: 9),
                _PulseBox(width: 96, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading stand-in for [RecipeListCard]: same 88dp height and 72dp
/// thumbnail, three lines on the right.
class RecipeRowSkeleton extends StatelessWidget {
  const RecipeRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      height: RecipeListCard.height,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PulseBox(width: 72, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PulseBox(width: 160, height: 15),
                const SizedBox(height: 9),
                _PulseBox(width: 120, height: 12),
                const SizedBox(height: 9),
                _PulseBox(width: 80, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
