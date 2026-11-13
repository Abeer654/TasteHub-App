// ============================================================
//  recipe.dart - the recipe shapes returned by the TasteHub API
//
//  API.md is the source of truth. Keep these field names in sync.
// ============================================================

String _asString(Object? value) => value is String ? value : '';

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

class Rating {
  const Rating({
    required this.userId,
    required this.userName,
    required this.stars,
    required this.proofImageRef,
  });

  final int userId;
  final String userName;
  final int stars;
  final String proofImageRef;

  factory Rating.fromJson(Map<String, dynamic> json) {
    return Rating(
      userId: _asInt(json['userId']),
      userName: _asString(json['userName']),
      stars: _asInt(json['stars']),
      proofImageRef: _asString(json['proofImageRef']),
    );
  }
}

/// The editable part of a recipe. Used by the add/edit form and by the
/// AI draft preview, where the server returns a recipe object without an id.
class RecipeInput {
  RecipeInput({
    required this.title,
    this.dish = 'My Recipes',
    this.mainIngredient = '',
    required this.ingredients,
    required this.steps,
    this.cookingTime = 0,
    this.imageRef = '',
    this.youtubeUrl = '',
  });

  String title;
  String dish;
  String mainIngredient;
  List<String> ingredients;
  List<String> steps;
  int cookingTime;
  String imageRef;
  String youtubeUrl;

  factory RecipeInput.fromJson(Map<String, dynamic> json) {
    return RecipeInput(
      title: _asString(json['title']),
      dish: _asString(json['dish']).isEmpty
          ? 'My Recipes'
          : _asString(json['dish']),
      mainIngredient: _asString(json['mainIngredient']),
      ingredients: _asStringList(json['ingredients']),
      steps: _asStringList(json['steps']),
      cookingTime: _asInt(json['cookingTime']),
      imageRef: _asString(json['imageRef']),
      youtubeUrl: _asString(json['youtubeUrl']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title.trim(),
      'dish': dish.trim().isEmpty ? 'My Recipes' : dish.trim(),
      'mainIngredient': mainIngredient.trim(),
      'ingredients': ingredients
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      'steps': steps
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
      'cookingTime': cookingTime,
      'imageRef': imageRef.trim(),
      'youtubeUrl': youtubeUrl.trim(),
    };
  }
}

class Recipe {
  const Recipe({
    required this.id,
    required this.title,
    required this.dish,
    required this.ownerId,
    required this.ownerName,
    required this.mainIngredient,
    required this.cookingTime,
    required this.imageRef,
    required this.youtubeUrl,
    required this.averageRating,
    required this.ratingCount,
    required this.myRating,
    required this.myRatingProofImageRef,
    this.createdAt,
    this.updatedAt,
    this.ingredients = const [],
    this.steps = const [],
    this.ratings = const [],
  });

  final int id;
  final String title;
  final String dish;
  final int ownerId;
  final String ownerName;
  final String mainIngredient;
  final int cookingTime;
  final String imageRef;
  final String youtubeUrl;
  final double averageRating;
  final int ratingCount;
  final int myRating;
  final String myRatingProofImageRef;
  final String? createdAt;
  final String? updatedAt;
  final List<String> ingredients;
  final List<String> steps;
  final List<Rating> ratings;

  bool get isRated => ratingCount > 0;
  bool get hasDetail => ingredients.isNotEmpty || steps.isNotEmpty;

  factory Recipe.fromJson(Map<String, dynamic> json) {
    final ratings = json['ratings'];

    return Recipe(
      id: _asInt(json['id']),
      title: _asString(json['title']),
      dish: _asString(json['dish']),
      ownerId: _asInt(json['ownerId']),
      ownerName: _asString(json['ownerName']),
      mainIngredient: _asString(json['mainIngredient']),
      cookingTime: _asInt(json['cookingTime']),
      imageRef: _asString(json['imageRef']),
      youtubeUrl: _asString(json['youtubeUrl']),
      averageRating: _asDouble(json['averageRating']),
      ratingCount: _asInt(json['ratingCount']),
      myRating: _asInt(json['myRating']),
      myRatingProofImageRef: _asString(json['myRatingProofImageRef']),
      createdAt: json['createdAt'] is String
          ? json['createdAt'] as String
          : null,
      updatedAt: json['updatedAt'] is String
          ? json['updatedAt'] as String
          : null,
      ingredients: _asStringList(json['ingredients']),
      steps: _asStringList(json['steps']),
      ratings: ratings is List
          ? ratings
                .whereType<Map<String, dynamic>>()
                .map(Rating.fromJson)
                .toList(growable: false)
          : const [],
    );
  }

  RecipeInput toInput() {
    return RecipeInput(
      title: title,
      dish: dish,
      mainIngredient: mainIngredient,
      ingredients: List<String>.from(ingredients),
      steps: List<String>.from(steps),
      cookingTime: cookingTime,
      imageRef: imageRef,
      youtubeUrl: youtubeUrl,
    );
  }

  Recipe withRating(RatingSummary summary) {
    return Recipe(
      id: id,
      title: title,
      dish: dish,
      ownerId: ownerId,
      ownerName: ownerName,
      mainIngredient: mainIngredient,
      cookingTime: cookingTime,
      imageRef: imageRef,
      youtubeUrl: youtubeUrl,
      averageRating: summary.averageRating,
      ratingCount: summary.ratingCount,
      myRating: summary.myRating,
      myRatingProofImageRef: summary.myRatingProofImageRef,
      createdAt: createdAt,
      updatedAt: updatedAt,
      ingredients: ingredients,
      steps: steps,
      ratings: ratings,
    );
  }
}

class RatingSummary {
  const RatingSummary({
    required this.averageRating,
    required this.ratingCount,
    required this.myRating,
    required this.myRatingProofImageRef,
  });

  final double averageRating;
  final int ratingCount;
  final int myRating;
  final String myRatingProofImageRef;

  factory RatingSummary.fromJson(Map<String, dynamic> json) {
    return RatingSummary(
      averageRating: _asDouble(json['averageRating']),
      ratingCount: _asInt(json['ratingCount']),
      myRating: _asInt(json['myRating']),
      myRatingProofImageRef: _asString(json['myRatingProofImageRef']),
    );
  }
}
