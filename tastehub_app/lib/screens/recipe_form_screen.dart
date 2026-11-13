// ============================================================
//  recipe_form_screen.dart - add and edit a recipe
//
//  This file owns state only: controllers, saving, photo upload and the
//  unsaved-changes guard. The visual sections are independent files under
//  screens/recipe_form/:
//
//    basics_fields.dart      title, dish, ingredient, time, YouTube
//    ingredient_editor.dart  ingredient rows
//    step_editor.dart        numbered step rows
//    ai_draft_banner.dart    review note when opened from an AI draft
//    save_bar.dart           sticky Save / unsaved changes bar
//
//  The main recipe photo uses widgets/recipe_photo_field.dart. It is a
//  different concept from a rating photo, which lives on the detail screen.
// ============================================================

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../theme.dart';
import '../widgets/recipe_photo_field.dart';
import '../widgets/section_card.dart';
import 'recipe_form/ai_draft_banner.dart';
import 'recipe_form/basics_fields.dart';
import 'recipe_form/ingredient_editor.dart';
import 'recipe_form/save_bar.dart';
import 'recipe_form/step_editor.dart';

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
  bool _dirty = false;
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

    for (final controller in [
      _title,
      _dish,
      _mainIngredient,
      _cookingTime,
      _imageRef,
      _youtubeUrl,
    ]) {
      controller.addListener(_markDirty);
    }

    for (final ingredient in source?.ingredients ?? const <String>[]) {
      _ingredients.add(_newRowController(ingredient));
    }
    if (_ingredients.isEmpty) _ingredients.add(_newRowController());

    for (final step in source?.steps ?? const <String>[]) {
      _steps.add(_newRowController(step));
    }
    if (_steps.isEmpty) _steps.add(_newRowController());
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

  TextEditingController _newRowController([String text = '']) {
    final controller = TextEditingController(text: text);
    controller.addListener(_markDirty);
    return controller;
  }

  void _markDirty() {
    if (_dirty || !mounted) return;
    setState(() => _dirty = true);
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
      _snack('Recipe photo uploaded.');
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
    setState(() => _localPreview = null);
    _imageRef.clear();
    _markDirty();
  }

  void _onPhotoUrlChanged(String _) {
    if (_localPreview != null) {
      setState(() => _localPreview = null);
    }
    _markDirty();
  }

  Future<bool> _confirmDiscard() async {
    final colors = context.tasteHubColors;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits to this recipe will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop || _saving) return;

    final discard = await _confirmDiscard();
    if (!mounted || !discard) return;
    setState(() => _dirty = false);
    Navigator.of(context).pop();
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
      setState(() => _dirty = false);
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
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Could not save the recipe: $error', isError: true);
    }
  }

  void _addIngredient() {
    setState(() {
      _ingredients.add(_newRowController());
      _dirty = true;
    });
  }

  void _removeIngredient(int index) {
    if (_ingredients.length == 1) {
      _ingredients.first.clear();
      _markDirty();
      return;
    }
    setState(() {
      _ingredients.removeAt(index).dispose();
      _dirty = true;
    });
  }

  void _addStep() {
    setState(() {
      _steps.add(_newRowController());
      _dirty = true;
    });
  }

  void _removeStep(int index) {
    if (_steps.length == 1) {
      _steps.first.clear();
      _markDirty();
      return;
    }
    setState(() {
      _steps.removeAt(index).dispose();
      _dirty = true;
    });
  }

  void _cancel() {
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(title: Text(_isEditing ? 'Edit recipe' : 'Add recipe')),
        bottomNavigationBar: RecipeSaveBar(
          dirty: _dirty,
          saving: _saving,
          uploading: _uploadingPhoto,
          isEditing: _isEditing,
          onSave: _save,
          onCancel: _cancel,
        ),
        body: SingleChildScrollView(
          padding: TasteHubLayout.pagePadding(context),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.draftMessage != null) ...[
                      AiDraftBanner(
                        message: widget.draftMessage!,
                        inferredFields: widget.inferredFields,
                        followUpQuestions: widget.followUpQuestions,
                      ),
                      const SizedBox(height: TasteHubSpacing.section),
                    ],
                    SectionCard(
                      title: 'Recipe details',
                      icon: Icons.restaurant_menu_rounded,
                      subtitle: 'Name the dish and add the basics.',
                      child: RecipeBasicsFields(
                        title: _title,
                        dish: _dish,
                        mainIngredient: _mainIngredient,
                        cookingTime: _cookingTime,
                        youtubeUrl: _youtubeUrl,
                        isEditing: _isEditing,
                        enabled: !_saving,
                      ),
                    ),
                    const SizedBox(height: TasteHubSpacing.section),
                    SectionCard(
                      title: 'Recipe photo',
                      icon: Icons.photo_camera_outlined,
                      subtitle: 'The main photo shown on the dish card.',
                      child: RecipePhotoField(
                        controller: _imageRef,
                        resolveMediaUrl: widget.api.resolveMediaUrl,
                        localPreview: _localPreview,
                        uploading: _uploadingPhoto,
                        enabled: !_saving,
                        onChanged: _onPhotoUrlChanged,
                        onPick: _pickPhoto,
                        onRemove: _removePhoto,
                      ),
                    ),
                    const SizedBox(height: TasteHubSpacing.section),
                    SectionCard(
                      title: 'Ingredients',
                      icon: Icons.shopping_basket_outlined,
                      subtitle: 'What you need for this recipe.',
                      child: IngredientEditor(
                        controllers: _ingredients,
                        enabled: !_saving,
                        onAdd: _addIngredient,
                        onRemove: _removeIngredient,
                      ),
                    ),
                    const SizedBox(height: TasteHubSpacing.section),
                    SectionCard(
                      title: 'Cooking steps',
                      icon: Icons.local_fire_department_outlined,
                      subtitle: 'One action per step is easiest to follow.',
                      child: StepEditor(
                        controllers: _steps,
                        enabled: !_saving,
                        onAdd: _addStep,
                        onRemove: _removeStep,
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
