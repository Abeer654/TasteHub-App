import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tastehub_app/services/api_client.dart';

/// One recipe summary, shaped like `GET /api/recipes` and the search route.
///
/// Seed recipes have an empty [imageRef] on purpose: the app keeps the warm
/// gradient placeholder until a user uploads a photo or adds an image URL.
Map<String, dynamic> recipeSummaryJson({
  int id = 1,
  String title = 'Chicken Biryani',
  String dish = 'Biryani',
  int ownerId = 1,
  String ownerName = 'junaid',
  double averageRating = 4.5,
  int ratingCount = 2,
  int myRating = 5,
  String imageRef = '',
  String myRatingProofImageRef = '',
  String? createdAt = '2026-10-20T18:00:00Z',
}) {
  return {
    'id': id,
    'title': title,
    'dish': dish,
    'ownerId': ownerId,
    'ownerName': ownerName,
    'mainIngredient': 'rice',
    'cookingTime': 60,
    'imageRef': imageRef,
    'youtubeUrl': 'https://www.youtube.com/results?search_query=biryani',
    'averageRating': averageRating,
    'ratingCount': ratingCount,
    'myRating': myRating,
    'myRatingProofImageRef': myRatingProofImageRef,
    'createdAt': createdAt,
    'updatedAt': null,
  };
}

/// Two recipes in each of two dishes. The numbers deliberately make the
/// ranking visible: Beef Biryani beats Chicken Biryani, and Mutton Karahi is
/// new/unrated so it must come after Chicken Karahi and be marked "New".
List<Map<String, dynamic>> demoRecipeSummaries() {
  return [
    recipeSummaryJson(
      id: 1,
      title: 'Chicken Biryani',
      dish: 'Biryani',
      averageRating: 4.0,
      ratingCount: 2,
    ),
    recipeSummaryJson(
      id: 2,
      title: 'Beef Biryani',
      dish: 'Biryani',
      averageRating: 4.5,
      ratingCount: 1,
      createdAt: '2026-10-19T18:00:00Z',
    ),
    recipeSummaryJson(
      id: 3,
      title: 'Chicken Karahi',
      dish: 'Karahi',
      averageRating: 4.8,
      ratingCount: 3,
      createdAt: '2026-10-18T18:00:00Z',
    ),
    recipeSummaryJson(
      id: 4,
      title: 'Mutton Karahi',
      dish: 'Karahi',
      averageRating: 0,
      ratingCount: 0,
      myRating: 0,
      createdAt: '2026-11-01T18:00:00Z',
    ),
  ];
}

/// The full detail response for [summary] (or the default Chicken Biryani).
Map<String, dynamic> recipeDetailJson([Map<String, dynamic>? summary]) {
  return {
    ...(summary ?? recipeSummaryJson()),
    'ingredients': ['rice', 'chicken', 'yogurt'],
    'steps': ['Marinate the chicken.', 'Layer with rice and cook.'],
    'ratings': [
      {'userId': 1, 'userName': 'junaid', 'stars': 5, 'proofImageRef': ''},
      {
        'userId': 2,
        'userName': 'guest',
        'stars': 4,
        'proofImageRef': 'https://example.com/proof.jpg',
      },
    ],
  };
}

http.Response jsonResponse(int status, Object body) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Map<String, dynamic> _userFor(String username) {
  return {
    'id': username == 'guest' ? 2 : (username == 'newcook' ? 3 : 1),
    'username': username,
  };
}

/// A small in-memory server that follows the real API contract closely enough
/// for the widget tests. Pass [requests] to inspect what the app sent.
ApiClient fakeApiClient({
  List<http.Request>? requests,
  List<Map<String, dynamic>>? recipes,
}) {
  final store = (recipes ?? demoRecipeSummaries()).toList();
  var nextId = 100;

  Map<String, dynamic>? findRecipe(int id) {
    for (final recipe in store) {
      if (recipe['id'] == id) return recipe;
    }
    return null;
  }

  final client = MockClient((request) async {
    requests?.add(request);
    final path = request.url.path;
    final method = request.method;

    // ---- accounts ----
    if (method == 'POST' && path == '/api/auth/login') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['password'] == 'wrong') {
        return jsonResponse(401, {'error': 'Wrong username or password.'});
      }
      final username = (body['username'] as String?) ?? 'junaid';
      return jsonResponse(200, {
        'token': 'test-token-$username',
        'user': _userFor(username),
      });
    }

    if (method == 'POST' && path == '/api/auth/signup') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final username = (body['username'] as String?) ?? 'newcook';
      if (username == 'junaid') {
        return jsonResponse(409, {'error': 'That username is already taken.'});
      }
      return jsonResponse(201, {
        'token': 'test-token-$username',
        'user': _userFor(username),
      });
    }

    if (method == 'GET' && path == '/api/auth/me') {
      final header = request.headers['authorization'] ?? '';
      final token = header.startsWith('Bearer ') ? header.substring(7) : '';
      final username = token.startsWith('test-token-')
          ? token.substring('test-token-'.length)
          : '';
      if (username.isEmpty) {
        return jsonResponse(401, {'error': 'Please log in first.'});
      }
      return jsonResponse(200, {'user': _userFor(username)});
    }

    if (method == 'POST' && path == '/api/auth/logout') {
      return jsonResponse(200, {'loggedOut': true});
    }

    // ---- photo upload ----
    if (method == 'POST' && path == '/api/images') {
      return jsonResponse(201, {
        'imageRef': '/uploads/img_test123.png',
        'contentType': 'image/png',
        'bytes': 68,
      });
    }

    // ---- recipes ----
    if (method == 'GET' && path == '/api/recipes') {
      return jsonResponse(200, store);
    }

    if (method == 'GET' && path == '/api/search') {
      final query = (request.url.queryParameters['q'] ?? '').toLowerCase();
      if (query.isEmpty) {
        return jsonResponse(200, {'query': '', 'results': <Object>[]});
      }
      final matches = store.where((recipe) {
        final title = '${recipe['title']}'.toLowerCase();
        final dish = '${recipe['dish']}'.toLowerCase();
        // The real API is fuzzy; exact matches are enough for these tests.
        return title.contains(query) ||
            dish.contains(query) ||
            (query == 'briyani' && title.contains('biryani'));
      }).toList();
      return jsonResponse(200, {'query': query, 'results': matches});
    }

    final ratingMatch = RegExp(r'^/api/recipes/(\d+)/rating$').firstMatch(path);
    if (method == 'PUT' && ratingMatch != null) {
      final id = int.parse(ratingMatch.group(1)!);
      final recipe = findRecipe(id);
      if (recipe == null) {
        return jsonResponse(404, {'error': 'Recipe not found'});
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final stars = (body['stars'] as num).toInt();
      recipe['myRating'] = stars;
      recipe['ratingCount'] = (recipe['ratingCount'] as int) + 1;
      recipe['averageRating'] = stars.toDouble();
      if (body.containsKey('proofImageRef')) {
        recipe['myRatingProofImageRef'] = body['proofImageRef'];
      }
      return jsonResponse(200, {
        'averageRating': recipe['averageRating'],
        'ratingCount': recipe['ratingCount'],
        'myRating': recipe['myRating'],
        'myRatingProofImageRef': recipe['myRatingProofImageRef'],
      });
    }

    final detailMatch = RegExp(r'^/api/recipes/(\d+)$').firstMatch(path);
    if (method == 'GET' && detailMatch != null) {
      final recipe = findRecipe(int.parse(detailMatch.group(1)!));
      return recipe == null
          ? jsonResponse(404, {'error': 'Recipe not found'})
          : jsonResponse(200, recipeDetailJson(recipe));
    }

    if (method == 'PUT' && detailMatch != null) {
      final recipe = findRecipe(int.parse(detailMatch.group(1)!));
      if (recipe == null) {
        return jsonResponse(404, {'error': 'Recipe not found'});
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      recipe.addAll(body.map((key, value) => MapEntry(key, value)));
      recipe['updatedAt'] = '2026-11-12T12:00:00Z';
      return jsonResponse(200, recipeDetailJson(recipe));
    }

    if (method == 'DELETE' && detailMatch != null) {
      final id = int.parse(detailMatch.group(1)!);
      store.removeWhere((recipe) => recipe['id'] == id);
      return jsonResponse(200, {'deleted': true, 'id': id});
    }

    if (method == 'POST' && path == '/api/recipes') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final recipe = recipeSummaryJson(
        id: nextId++,
        title: (body['title'] as String?) ?? 'New recipe',
        dish: (body['dish'] as String?) ?? 'My Recipes',
        ownerId: 1,
        ownerName: 'junaid',
        averageRating: 0,
        ratingCount: 0,
        myRating: 0,
        imageRef: (body['imageRef'] as String?) ?? '',
        createdAt: '2026-11-12T12:00:00Z',
      );
      recipe['mainIngredient'] = (body['mainIngredient'] as String?) ?? '';
      recipe['cookingTime'] = body['cookingTime'] ?? 0;
      recipe['youtubeUrl'] = body['youtubeUrl'] ?? '';
      store.add(recipe);
      return jsonResponse(201, recipeDetailJson(recipe));
    }

    if (method == 'POST' && path == '/api/recipes/parse') {
      return jsonResponse(200, {
        'message': 'That sounds delicious.',
        'recipe': {
          'dish': 'Biryani',
          'title': 'Chicken Biryani',
          'mainIngredient': 'rice',
          'ingredients': ['rice', 'chicken'],
          'steps': ['Marinate the chicken.', 'Cook with rice.'],
          'cookingTime': 60,
          'imageRef': '',
          'youtubeUrl': '',
        },
        'inferredFields': ['cookingTime'],
        'followUpQuestions': ['How much rice did you use?'],
        'source': 'gemini',
      });
    }

    return jsonResponse(404, {'error': 'Not found'});
  });

  return ApiClient(client: client, baseUrl: 'http://example.test:8080');
}
