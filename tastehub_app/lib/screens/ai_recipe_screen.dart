// ============================================================
//  ai_recipe_screen.dart - describe a dish, review the AI draft
// ============================================================

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../theme.dart';
import 'recipe_form_screen.dart';

class AiRecipeScreen extends StatefulWidget {
  const AiRecipeScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<AiRecipeScreen> createState() => _AiRecipeScreenState();
}

class _AiRecipeScreenState extends State<AiRecipeScreen> {
  final TextEditingController _description = TextEditingController();

  bool _loading = false;
  String? _error;

  static const List<String> _examples = [
    'Chicken biryani with rice, yogurt and warm spices, cooked for an hour.',
    'Crispy fries tossed with salt and chilli powder.',
    'Beef nihari simmered slowly for three hours with ginger and garam masala.',
  ];

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _createDraft() async {
    FocusScope.of(context).unfocus();
    final text = _description.text.trim();

    if (text.length < 10) {
      setState(() {
        _error = 'Describe the dish in at least one sentence.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final draft = await widget.api.parseRecipe(text);
      if (!mounted) return;

      // Push the form (instead of replacing this screen) so the home screen
      // waits for "Save recipe" before it reloads. Then close this screen with
      // the form's result.
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => RecipeFormScreen(
            api: widget.api,
            initial: draft.recipe,
            draftMessage: draft.message,
            inferredFields: draft.inferredFields,
            followUpQuestions: draft.followUpQuestions,
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(changed);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _writeManually() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RecipeFormScreen(api: widget.api),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(changed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Describe with AI')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildIntro(context),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Your description',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Write it the way you would tell a friend. Typos and '
                        'Roman Urdu are fine.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _description,
                        minLines: 6,
                        maxLines: 12,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText:
                              'I made chicken biryani last night with rice, '
                              'chicken, yogurt, onions and spices. I marinated '
                              'the chicken, fried the onions, layered it with '
                              'rice and cooked it on low heat for an hour...',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final example in _examples)
                            ActionChip(
                              label: Text(
                                '${example.split(' ').take(4).join(' ')}...',
                              ),
                              onPressed: _loading
                                  ? null
                                  : () {
                                      _description.text = example;
                                      _description.selection =
                                          TextSelection.collapsed(
                                            offset: example.length,
                                          );
                                    },
                            ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        _ErrorNote(message: _error!),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _loading ? null : _createDraft,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 17),
                        ),
                        icon: _loading
                            ? SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.onAccent,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_rounded, size: 19),
                        label: Text(
                          _loading
                              ? 'Asking Gemini for a draft...'
                              : 'Create AI draft',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: colors.muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Nothing is saved until you review the draft and press '
                        '"Save recipe".',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Center(
                  child: TextButton.icon(
                    onPressed: _loading ? null : _writeManually,
                    icon: const Icon(Icons.edit_note_rounded, size: 19),
                    label: const Text('Write it manually instead'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.accent.withValues(alpha: 0.12),
            colors.gold.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome_rounded, color: colors.accent),
          ),
          const SizedBox(height: 14),
          Text(
            'Tell us what you cooked.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Gemini turns your description into a structured recipe. You can '
            'edit every field before it is saved.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.muted),
          ),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }
}
