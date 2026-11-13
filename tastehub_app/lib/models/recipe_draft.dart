// ============================================================
//  recipe_draft.dart - response of POST /api/recipes/parse
// ============================================================

import 'recipe.dart';

class RecipeDraft {
  const RecipeDraft({
    required this.message,
    required this.recipe,
    required this.inferredFields,
    required this.followUpQuestions,
    required this.source,
  });

  final String message;
  final RecipeInput recipe;
  final List<String> inferredFields;
  final List<String> followUpQuestions;
  final String source;

  factory RecipeDraft.fromJson(Map<String, dynamic> json) {
    final recipe = json['recipe'];
    if (recipe is! Map<String, dynamic>) {
      throw const FormatException('The draft is missing its recipe');
    }

    final inferred = json['inferredFields'];
    final questions = json['followUpQuestions'];

    return RecipeDraft(
      message: json['message'] is String ? json['message'] as String : '',
      recipe: RecipeInput.fromJson(recipe),
      inferredFields: inferred is List
          ? inferred.whereType<String>().toList(growable: false)
          : const [],
      followUpQuestions: questions is List
          ? questions.whereType<String>().toList(growable: false)
          : const [],
      source: json['source'] is String ? json['source'] as String : 'gemini',
    );
  }
}
