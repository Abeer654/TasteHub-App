// ============================================================
//  basics_fields.dart - title, dish, ingredient, time and YouTube fields
//
//  Owns: the "Recipe details" form fields and their validation. The photo
//  picker is a separate section; the save button lives in the sticky bar.
//
//  E-01  the Dish field is locked once a recipe exists.
//  E-02  YouTube accepts a link to exactly one video (watch / youtu.be /
//        shorts / m.youtube), with a Paste button and a 16:9 preview.
//  E-03  cooking time is minutes only, with 15/30/45/60 quick chips.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';

/// E-02: the video id, or null when [url] is not a single-video link.
///
/// Kept as a top-level helper so the rule can be unit-tested without a
/// widget tree (see youtube_validation_test.dart).
String? youtubeVideoId(String url) {
  final text = url.trim();
  if (text.isEmpty) return null;

  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  if (uri.host.isEmpty) return null;

  // A playlist link is still a YouTube link, but it does not open one
  // video, so it fails the same as a search or channel URL.
  if (uri.queryParameters.containsKey('list')) return null;

  final host = uri.host.toLowerCase();
  final bare = host.startsWith('www.') ? host.substring(4) : host;
  final segments =
      uri.pathSegments.where((segment) => segment.isNotEmpty).toList();

  bool goodId(String? id) =>
      id != null && RegExp(r'^[A-Za-z0-9_-]{5,}$').hasMatch(id);

  if (bare == 'youtu.be') {
    // https://youtu.be/<id>
    return segments.length == 1 && goodId(segments.single)
        ? segments.single
        : null;
  }

  if (bare == 'youtube.com' || bare.endsWith('.youtube.com')) {
    if (segments.length == 1 && segments.single == 'watch') {
      final id = uri.queryParameters['v'];
      return goodId(id) ? id : null;
    }
    if (segments.length == 2 && segments.first == 'shorts') {
      final id = segments[1];
      return goodId(id) ? id : null;
    }
    // /results, /playlist, /channel, /@user, /embed ... - not one video.
    return null;
  }

  return null;
}

/// E-02: the one error message the spec asks for, or null when valid/empty.
String? youtubeUrlError(String? url) {
  final text = (url ?? '').trim();
  if (text.isEmpty) return null;
  return youtubeVideoId(text) == null
      ? 'Paste a link to a single YouTube video.'
      : null;
}

/// E-03: minutes only, 1-1440 (24 hours). Empty stays allowed - the field
/// is optional and 0 means "time not set".
String? cookingTimeError(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;

  final minutes = int.tryParse(text);
  if (minutes == null || minutes < 1 || minutes > 1440) {
    return 'Enter a time between 1 and 1440 minutes.';
  }
  return null;
}

class RecipeBasicsFields extends StatefulWidget {
  const RecipeBasicsFields({
    super.key,
    required this.title,
    required this.dish,
    required this.mainIngredient,
    required this.cookingTime,
    required this.youtubeUrl,
    required this.isEditing,
    required this.enabled,
  });

  final TextEditingController title;
  final TextEditingController dish;
  final TextEditingController mainIngredient;
  final TextEditingController cookingTime;
  final TextEditingController youtubeUrl;
  final bool isEditing;
  final bool enabled;

  @override
  State<RecipeBasicsFields> createState() => _RecipeBasicsFieldsState();
}

class _RecipeBasicsFieldsState extends State<RecipeBasicsFields> {
  @override
  void initState() {
    super.initState();
    widget.youtubeUrl.addListener(_refresh);
    widget.cookingTime.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant RecipeBasicsFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.youtubeUrl, widget.youtubeUrl)) {
      oldWidget.youtubeUrl.removeListener(_refresh);
      widget.youtubeUrl.addListener(_refresh);
    }
    if (!identical(oldWidget.cookingTime, widget.cookingTime)) {
      oldWidget.cookingTime.removeListener(_refresh);
      widget.cookingTime.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.youtubeUrl.removeListener(_refresh);
    widget.cookingTime.removeListener(_refresh);
    super.dispose();
  }

  /// Both fields drive UI that lives outside their own text: the YouTube
  /// preview and the selected quick chip. The controllers notify on every
  /// change (typing or a chip tap), so one rebuild covers them.
  void _refresh() {
    if (mounted) setState(() {});
  }

  void _setTime(int minutes) {
    widget.cookingTime.text = '$minutes';
  }

  Future<void> _pasteYoutube() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    widget.youtubeUrl.text = text;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: widget.title,
          enabled: widget.enabled,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Recipe title *',
            hintText: 'Chicken Biryani',
          ),
          validator: (value) {
            if ((value ?? '').trim().isEmpty) {
              return 'Give the recipe a title.';
            }
            return null;
          },
        ),
        const SizedBox(height: TasteHubSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 620;
            // E-01: once a recipe exists its dish is fixed, so the field
            // must look and behave locked rather than merely read-only.
            Widget dishField = TextFormField(
              controller: widget.dish,
              enabled: widget.enabled && !widget.isEditing,
              readOnly: widget.isEditing,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Dish',
                hintText: 'Biryani',
                suffixIcon: widget.isEditing
                    ? const Icon(Icons.lock_outline_rounded, size: 20)
                    : null,
                suffixIconConstraints: const BoxConstraints(
                  minHeight: 24,
                  minWidth: 24,
                ),
                helperText: widget.isEditing
                    ? 'Locked after creation.'
                    : 'Recipes with the same dish are ranked together.',
              ),
            );
            if (widget.isEditing) {
              dishField = Opacity(
                opacity: 0.6,
                child: Tooltip(
                  message: "A recipe can't move to another dish after it's "
                      'created.',
                  child: dishField,
                ),
              );
            }
            final ingredientField = TextFormField(
              controller: widget.mainIngredient,
              enabled: widget.enabled,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Main ingredient',
                hintText: 'rice',
              ),
            );

            if (!wide) {
              return Column(
                children: [
                  dishField,
                  const SizedBox(height: TasteHubSpacing.md),
                  ingredientField,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: dishField),
                const SizedBox(width: TasteHubSpacing.md),
                Expanded(child: ingredientField),
              ],
            );
          },
        ),
        const SizedBox(height: TasteHubSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final timeField = _cookingTimeField();
            final youtubeField = _youtubeField();

            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  timeField,
                  const SizedBox(height: TasteHubSpacing.md),
                  youtubeField,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 240, child: timeField),
                const SizedBox(width: TasteHubSpacing.md),
                Expanded(child: youtubeField),
              ],
            );
          },
        ),
      ],
    );
  }

  /// E-03: minutes only, with the four quick picks under the field.
  Widget _cookingTimeField() {
    final selected = widget.cookingTime.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.cookingTime,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Cooking time',
            hintText: '60',
            suffixText: 'min',
            prefixIcon: Icon(Icons.schedule_rounded, size: 19),
          ),
          validator: cookingTimeError,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final minutes in const [15, 30, 45, 60])
              _TimeChip(
                minutes: minutes,
                selected: selected == '$minutes',
                enabled: widget.enabled,
                onTap: () => _setTime(minutes),
              ),
          ],
        ),
      ],
    );
  }

  /// E-02: strict single-video validation (on blur and on save), a Paste
  /// button, and a 16:9 preview once the link is accepted.
  Widget _youtubeField() {
    final previewId = youtubeVideoId(widget.youtubeUrl.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.youtubeUrl,
          enabled: widget.enabled,
          // Last field of this section: finish editing instead of moving on.
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.url,
          autovalidateMode: AutovalidateMode.onUnfocus,
          decoration: InputDecoration(
            labelText: 'YouTube URL (optional)',
            hintText: 'https://www.youtube.com/watch?v=...',
            prefixIcon: const Icon(Icons.smart_display_outlined, size: 19),
            suffixIcon: IconButton(
              tooltip: 'Paste',
              icon: const Icon(Icons.content_paste_rounded, size: 19),
              onPressed: widget.enabled ? _pasteYoutube : null,
            ),
          ),
          // The detail screen only offers "Watch on YouTube" for a link
          // that opens a single video, so anything else (search results,
          // playlists, channels) is rejected instead of saved.
          validator: youtubeUrlError,
        ),
        if (previewId != null) ...[
          const SizedBox(height: TasteHubSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 120,
                  height: 68, // 16:9
                  child: Image.network(
                    'https://i.ytimg.com/vi/$previewId/mqdefault.jpg',
                    fit: BoxFit.cover,
                    // Never let a dead thumbnail break the form: fall
                    // back to the same play tile the detail screen uses.
                    errorBuilder: (context, error, stack) => ColoredBox(
                      color: context.tasteHubColors.field,
                      child: Icon(
                        Icons.smart_display_outlined,
                        color: context.tasteHubColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Single video link - the preview shows before you save.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.minutes,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Semantics(
      button: true,
      label: 'Set cooking time to $minutes minutes',
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? colors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? colors.accent : colors.line,
              ),
            ),
            child: Text(
              '$minutes',
              style: TextStyle(
                color: selected ? colors.onAccent : colors.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
