import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tastehub_app/models/recipe.dart';
import 'package:tastehub_app/services/api_client.dart';
import 'package:tastehub_app/services/api_exception.dart';

import 'support/api_fixtures.dart';

void main() {
  group('ApiClient reads', () {
    test('lists recipes with owner names and per-user ratings', () async {
      final api = fakeApiClient();
      final recipes = await api.listRecipes();

      expect(recipes, hasLength(4));
      final chicken = recipes.firstWhere((recipe) => recipe.id == 1);
      expect(chicken.title, 'Chicken Biryani');
      expect(chicken.averageRating, 4.0);
      expect(chicken.ownerId, 1);
      expect(chicken.ownerName, 'junaid');
      expect(chicken.myRating, 5);
    });

    test('loads one recipe with details and rating usernames', () async {
      final api = fakeApiClient();
      final recipe = await api.getRecipe(1);

      expect(recipe.ingredients, contains('chicken'));
      expect(recipe.steps, hasLength(2));
      expect(recipe.ratings, hasLength(2));
      expect(recipe.ratings.first.userName, 'junaid');
      expect(recipe.ratings.last.userName, 'guest');
    });

    test('sends the search text as a query parameter', () async {
      final requests = <http.Request>[];
      final api = fakeApiClient(requests: requests);

      final results = await api.search('briyani');

      expect(requests.last.url.queryParameters['q'], 'briyani');
      expect(results, hasLength(2));
      expect(results.first.title, 'Chicken Biryani');
    });

    test('resolves uploaded paths and external URLs', () async {
      final api = fakeApiClient();

      expect(api.resolveMediaUrl(''), '');
      expect(
        api.resolveMediaUrl('/uploads/img_abc.png'),
        'http://example.test:8080/uploads/img_abc.png',
      );
      expect(
        api.resolveMediaUrl('uploads/img_abc.png'),
        'http://example.test:8080/uploads/img_abc.png',
      );
      expect(
        api.resolveMediaUrl('https://example.com/photo.jpg'),
        'https://example.com/photo.jpg',
      );
      expect(api.resolveMediaUrl('not a link'), '');
    });
  });

  group('ApiClient authentication', () {
    test('logs in and returns the token and user', () async {
      final requests = <http.Request>[];
      final api = fakeApiClient(requests: requests);

      final session = await api.login('junaid', 'tastehub');

      final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(requests.last.url.path, '/api/auth/login');
      expect(body, {'username': 'junaid', 'password': 'tastehub'});
      expect(session.token, 'test-token-junaid');
      expect(session.user.id, 1);
      expect(session.user.username, 'junaid');
    });

    test('sends the bearer token on later requests', () async {
      final requests = <http.Request>[];
      final api = fakeApiClient(requests: requests);

      await api.login('junaid', 'tastehub');
      api.token = 'test-token-junaid';

      await api.listRecipes();
      expect(
        requests.last.headers['authorization'],
        'Bearer test-token-junaid',
      );

      await api.me();
      expect(
        requests.last.headers['authorization'],
        'Bearer test-token-junaid',
      );
    });

    test('rejects an invalid password', () async {
      final api = fakeApiClient();

      await expectLater(
        api.login('junaid', 'wrong'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'status',
            401,
          ),
        ),
      );
    });
  });

  group('ApiClient writes', () {
    test('creates a recipe with a JSON body', () async {
      final requests = <http.Request>[];
      final api = fakeApiClient(requests: requests);

      await api.addRecipe(RecipeInputForTest.biryani());

      final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(requests.last.method, 'POST');
      expect(body['title'], 'Chicken Biryani');
      expect(body['ingredients'], ['rice', 'chicken']);
    });

    test('sends stars with a proof only when asked', () async {
      final requests = <http.Request>[];
      final api = fakeApiClient(requests: requests);

      await api.rateRecipe(1, 5, proofImageRef: 'https://example.com/p.jpg');
      var body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(body, {'stars': 5, 'proofImageRef': 'https://example.com/p.jpg'});

      await api.rateRecipe(1, 4);
      body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(body, {'stars': 4});
    });

    test('uploads a photo as multipart with the token', () async {
      final requests = <http.Request>[];
      final api = fakeApiClient(requests: requests);
      api.token = 'test-token-junaid';

      final ref = await api.uploadImage(
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
        'photo.png',
      );

      expect(requests.last.method, 'POST');
      expect(requests.last.url.path, '/api/images');
      expect(
        requests.last.headers['authorization'],
        'Bearer test-token-junaid',
      );
      expect(
        requests.last.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(ref, '/uploads/img_test123.png');
    });

    test('parses a description without saving anything', () async {
      final requests = <http.Request>[];
      final api = fakeApiClient(requests: requests);

      final draft = await api.parseRecipe('Chicken biryani with rice.');

      expect(requests.last.url.path, '/api/recipes/parse');
      expect(requests.last.method, 'POST');
      expect(draft.recipe.title, 'Chicken Biryani');
      expect(draft.inferredFields, ['cookingTime']);
      expect(draft.followUpQuestions, hasLength(1));
    });
  });

  group('ApiClient errors', () {
    test('uses the server error message and status', () async {
      final api = ApiClient(
        client: MockClient(
          (_) async => jsonResponse(404, {'error': 'Recipe not found'}),
        ),
        baseUrl: 'http://example.test:8080',
      );

      await expectLater(
        api.getRecipe(99),
        throwsA(
          isA<ApiException>()
              .having((error) => error.message, 'message', 'Recipe not found')
              .having((error) => error.statusCode, 'status', 404),
        ),
      );
    });

    test('explains an unreachable server', () async {
      final api = ApiClient(
        client: MockClient((_) async {
          throw const SocketException('connection refused');
        }),
        baseUrl: 'http://127.0.0.1:8080',
      );

      await expectLater(
        api.listRecipes(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('Cannot reach the server'),
          ),
        ),
      );
    });

    test('rejects an invalid recipe list response', () async {
      final api = ApiClient(
        client: MockClient((_) async => jsonResponse(200, {'oops': true})),
        baseUrl: 'http://example.test:8080',
      );

      await expectLater(api.listRecipes(), throwsA(isA<ApiException>()));
    });
  });
}

class RecipeInputForTest {
  static RecipeInput biryani() {
    return RecipeInput(
      title: 'Chicken Biryani',
      dish: 'Biryani',
      mainIngredient: 'rice',
      ingredients: ['rice', 'chicken'],
      steps: ['Marinate the chicken.', 'Cook with rice.'],
      cookingTime: 60,
    );
  }
}
