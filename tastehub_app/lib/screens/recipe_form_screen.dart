// ============================================================
//  recipe_form_screen.dart - add and edit a recipe
//
//  The same screen is used for AI drafts. In that case the fields
//  arrive pre-filled, a banner explains what Gemini inferred, and the
//  user still has to press "Save recipe".
// ============================================================

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recipe.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../theme.dart';

class RecipeFormScreen extends StatefulWidget {
  const RecipeFormScreen({
    super.key,
    required this.api,
    this.existing,
    this.initial,
    this.initialDish,
    this.draftMessage,
    this.inferredFields = const [],
    this.followUpQuestions = const [],
  }) : assert(existing == null || initial == null);

  final ApiClient api;
  final Recipe? existing;
  final RecipeInput? initial;
  final String? initialDish;
  final String? draftMessage;
  final List<String> inferredFields;
  final List<String> followUpQuestions;

  @override
  State<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends State<RecipeFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _dish;
  late final TextEditingController _mainIngredient;
  late final TextEditingController _cookingTime;
  late final TextEditingController _imageRef;
  late final TextEditingController _youtubeUrl;

  final List<TextEditingController> _ingredients = [];
  final List<TextEditingController> _steps = [];

  bool _saving = false;
  bool _uploadingPhoto = false;
  Uint8List? _localPreview;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final source = widget.existing?.toInput() ?? widget.initial;

    _title = TextEditingController(text: source?.title ?? '');
    _dish = TextEditingController(
      text: source?.dish ?? widget.initialDish ?? '',
    );
    _mainIngredient = TextEditingController(text: source?.mainIngredient ?? '');
    _cookingTime = TextEditingController(
      text: (source?.cookingTime ?? 0) > 0 ? '${source!.cookingTime}' : '',
    );
    _imageRef = TextEditingController(text: source?.imageRef ?? '');
    _youtubeUrl = TextEditingController(text: source?.youtubeUrl ?? '');

    for (final ingredient in source?.ingredients ?? const <String>[]) {
      _ingredients.add(TextEditingController(text: ingredient));
    }
    if (_ingredients.isEmpty) _ingredients.add(TextEditingController());

    for (final step in source?.steps ?? const <String>[]) {
      _steps.add(TextEditingController(text: step));
    }
    if (_steps.isEmpty) _steps.add(TextEditingController());
  }

  @override
  void dispose() {
    _title.dispose();
    _dish.dispose();
    _mainIngredient.dispose();
    _cookingTime.dispose();
    _imageRef.dispose();
    _youtubeUrl.dispose();
    for (final controller in _ingredients) {
      controller.dispose();
    }
    for (final controller in _steps) {
      controller.dispose();
    }
    super.dispose();
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? context.tasteHubColors.error : null,
        ),
      );
  }

  /// Picks a real photo from the device. The file is uploaded immediately;
  /// the returned /uploads/... path is what the recipe stores.
  Future<void> _pickPhoto() async {
    if (_uploadingPhoto || _saving) return;

    const typeGroup = XTypeGroup(
      label: 'Photos',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
    );

    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [typeGroup]);
    } catch (error) {
      _snack('Could not open the file picker: $error', isError: true);
      return;
    }
    if (file == null || !mounted) return;

    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        _snack('Choose an image smaller than 10 MB.', isError: true);
        return;
      }

      setState(() {
        _uploadingPhoto = true;
        _localPreview = bytes;
      });

      final imageRef = await widget.api.uploadImage(bytes, file.name);
      if (!mounted) return;
      _imageRef.text = imageRef;
      _snack('Photo uploaded.');
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _localPreview = null);
        _snack(error.message, isError: true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _localPreview = null);
        _snack('Could not upload the photo: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _removePhoto() {
    setState(() {
      _imageRef.clear();
      _localPreview = null;
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final ingredients = _ingredients
        .map((controller) => controller.text.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final steps = _steps
        .map((controller) => controller.text.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    if (ingredients.isEmpty) {
      _snack('Add at least one ingredient.', isError: true);
      return;
    }
    if (steps.isEmpty) {
      _snack('Add at least one cooking step.', isError: true);
      return;
    }

    final input = RecipeInput(
      title: _title.text.trim(),
      dish: _dish.text.trim().isEmpty ? 'My Recipes' : _dish.text.trim(),
      mainIngredient: _mainIngredient.text.trim(),
      ingredients: ingredients,
      steps: steps,
      cookingTime: int.tryParse(_cookingTime.text.trim()) ?? 0,
      imageRef: _imageRef.text.trim(),
      youtubeUrl: _youtubeUrl.text.trim(),
    );

    setState(() => _saving = true);

    try {
      if (_isEditing) {
        await widget.api.updateRecipe(widget.existing!.id, input);
      } else {
        await widget.api.addRecipe(input);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Recipe updated.' : 'Recipe saved.'),
          ),
        );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(error.message, isError: true);
    }
  }

  void _addIngredient() {
    setState(() => _ingredients.add(TextEditingController()));
  }

  void _removeIngredient(int index) {
    if (_ingredients.length == 1) {
      _ingredients.first.clear();
      return;
    }
    setState(() {
      _ingredients.removeAt(index).dispose();
    });
  }

  void _addStep() {
    setState(() => _steps.add(TextEditingController()));
  }

  void _removeStep(int index) {
    if (_steps.length == 1) {
      _steps.first.clear();
      return;
    }
    setState(() {
      _steps.removeAt(index).dispose();
    });
  }

  Widget _buildPhotoField(BuildContext context) {
    final colors = context.tasteHubColors;
    final hasRef = _imageRef.text.trim().isNotEmpty;
    final resolved = widget.api.resolveMediaUrl(_imageRef.text);

    Widget preview;
    if (_localPreview != null) {
      preview = Image.memory(
        _localPreview!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _PhotoPlaceholder(colors: colors),
      );
    } else if (resolved.isNotEmpty) {
      preview = Image.network(
        resolved,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _PhotoPlaceholder(colors: colors),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _PhotoPlaceholder(colors: colors),
      );
    } else {
      preview = _PhotoPlaceholder(colors: colors);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photo', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Upload a real photo from this device, or paste an image URL.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(width: 116, height: 88, child: preview),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saving || _uploadingPhoto
                            ? null
                            : _pickPhoto,
                        icon: _uploadingPhoto
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.photo_library_outlined,
                                size: 17,
                              ),
                        label: Text(
                          _uploadingPhoto
                              ? 'Uploading...'
                              : hasRef
                              ? 'Replace photo'
                              : 'Upload photo',
                        ),
                      ),
                      if (hasRef || _localPreview != null)
                        TextButton(
                          onPressed: _saving ? null : _removePhoto,
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _imageRef,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) {
                      if (_localPreview != null) {
                        setState(() => _localPreview = null);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Image URL',
                      hintText: 'https://... or an uploaded /uploads/... path',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit recipe' : 'Add recipe'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.draftMessage != null) ...[
                    _AiDraftBanner(
                      message: widget.draftMessage!,
                      inferredFields: widget.inferredFields,
                      followUpQuestions: widget.followUpQuestions,
                    ),
                    const SizedBox(height: 20),
                  ],
                  _Section(
                    title: 'The basics',
                    icon: Icons.restaurant_menu_rounded,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _title,
                          textInputAction: TextInputAction.next,
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
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 620;
                            final dish = TextFormField(
                              controller: _dish,
                              readOnly: _isEditing,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Dish',
                                hintText: 'Biryani',
                                helperText: _isEditing
                                    ? 'The dish cannot change after creation.'
                                    : null,
                              ),
                            );
                            final ingredient = TextFormField(
                              controller: _mainIngredient,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Main ingredient',
                                hintText: 'rice',
                              ),
                            );

                            if (!wide) {
                              return Column(
                                children: [
                                  dish,
                                  const SizedBox(height: 14),
                                  ingredient,
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(child: dish),
                                const SizedBox(width: 14),
                                Expanded(child: ingredient),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 260,
                            child: TextFormField(
                              controller: _cookingTime,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Cooking time (minutes)',
                                hintText: '60',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _youtubeUrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'YouTube URL',
                            hintText: 'https://www.youtube.com/...',
                          ),
                        ),
                        const SizedBox(height: 18),
                        _buildPhotoField(context),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Section(
                    title: 'Ingredients',
                    icon: Icons.shopping_basket_outlined,
                    trailing: TextButton.icon(
                      onPressed: _saving ? null : _addIngredient,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add'),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < _ingredients.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _ingredients[i],
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      hintText: 'Ingredient ${i + 1}',
                                      prefixIcon: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 16,
                                          right: 10,
                                        ),
                                        child: Icon(
                                          Icons.circle,
                                          size: 7,
                                          color: context.tasteHubColors.accent,
                                        ),
                                      ),
                                      prefixIconConstraints:
                                          const BoxConstraints(minWidth: 34),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _saving
                                      ? null
                                      : () => _removeIngredient(i),
                                  tooltip: 'Remove ingredient',
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 19,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Section(
                    title: 'Cooking steps',
                    icon: Icons.local_fire_department_outlined,
                    trailing: TextButton.icon(
                      onPressed: _saving ? null : _addStep,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add'),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < _steps.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: context.tasteHubColors.accent
                                          .withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        color: context.tasteHubColors.accent,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: _steps[i],
                                    minLines: 1,
                                    maxLines: 4,
                                    keyboardType: TextInputType.multiline,
                                    decoration: InputDecoration(
                                      hintText: i == 0
                                          ? 'Describe the first step...'
                                          : 'Describe step ${i + 1}...',
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _saving
                                      ? null
                                      : () => _removeStep(i),
                                  tooltip: 'Remove step',
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 19,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _saving || _uploadingPhoto ? null : _save,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 16,
                          ),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 19),
                        label: Text(
                          _saving
                              ? 'Saving...'
                              : _isEditing
                              ? 'Save changes'
                              : 'Save recipe',
                        ),
                      ),
                    ],
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

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: colors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _AiDraftBanner extends StatelessWidget {
  const _AiDraftBanner({
    required this.message,
    required this.inferredFields,
    required this.followUpQuestions,
  });

  final String message;
  final List<String> inferredFields;
  final List<String> followUpQuestions;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.accent.withValues(alpha: 0.1),
            colors.gold.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: colors.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'AI draft - review before saving',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (inferredFields.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final field in inferredFields)
                  Chip(
                    label: Text('AI filled: $field'),
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      color: colors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: colors.card,
                    side: BorderSide(
                      color: colors.accent.withValues(alpha: 0.25),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          if (followUpQuestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Worth checking:',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: colors.muted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            for (final question in followUpQuestions)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '- $question',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.colors});

  final TasteHubColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.field,
      alignment: Alignment.center,
      child: Icon(
        Icons.photo_outlined,
        size: 30,
        color: colors.muted,
      ),
    );
  }
}
