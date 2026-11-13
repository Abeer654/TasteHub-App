// ============================================================
//  api_client.dart - the only place that talks HTTP
//
//  Every screen uses this class and receives plain models back, so the
//  rest of the app never deals with JSON or status codes.
//
//  Authentication:
//    - the server uses bearer tokens
//    - setToken() is called by SessionController after login/restore
//    - every request automatically sends the token when it is present
//
//  Uploads:
//    - uploadImage() posts a multipart form to /api/images
//    - the returned "/uploads/..." path is stored on the recipe
//    - resolveMediaUrl() turns that path into a full URL for Image.network
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/recipe.dart';
import '../models/recipe_draft.dart';
import '../models/user.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = _normalise(baseUrl ?? AppConfig.apiBaseUrl);

  final http.Client _client;
  final String baseUrl;

  /// Bearer token of the current session. Null/empty means anonymous.
  String? token;

  static const Duration _requestTimeout = Duration(seconds: 15);

  // Gemini can take a while; API.md allows up to a minute for a draft.
  static const Duration _aiTimeout = Duration(seconds: 90);

  bool get isLoggedIn => (token ?? '').isNotEmpty;

  static String _normalise(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return AppConfig.apiBaseUrl;
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  void _addAuth(http.BaseRequest request) {
    final current = token;
    if (current != null && current.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $current';
    }
  }

  /// Turns a stored image reference into something Image.network can load.
  /// Seed recipes use an empty reference and keep the gradient placeholder.
  String resolveMediaUrl(String reference) {
    final ref = reference.trim();
    if (ref.isEmpty) return '';
    if (ref.startsWith('http://') || ref.startsWith('https://')) return ref;
    if (ref.startsWith('/')) return '$baseUrl$ref';
    return '';
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration timeout = _requestTimeout,
  }) async {
    final request = http.Request(method, _uri(path, query))
      ..headers['Accept'] = 'application/json';
    _addAuth(request);

    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(
        'The server took too long to respond. Check that it is still running.',
      );
    } on SocketException {
      throw ApiException(
        'Cannot reach the server at $baseUrl. Start it with `make run`.',
      );
    } on http.ClientException catch (error) {
      throw ApiException(
        'Cannot reach the server at $baseUrl. ${error.message}',
      );
    }

    // Decode as UTF-8 even if the response omits a charset header.
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    dynamic decoded;

    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        throw ApiException(
          'The server sent an unexpected response (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          decoded is Map<String, dynamic> && decoded['error'] is String
          ? decoded['error'] as String
          : 'Request failed (${response.statusCode}).';
      throw ApiException(message, statusCode: response.statusCode);
    }

    return decoded;
  }

  Map<String, dynamic> _object(dynamic value, String description) {
    if (value is Map<String, dynamic>) return value;
    throw ApiException('The server returned an invalid $description.');
  }

  List<T> _list<T>(
    dynamic value,
    String description,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (value is! List) {
      throw ApiException('The server returned an invalid $description.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(parse)
        .toList(growable: false);
  }

  // ------------------------------------------------------------
  //  Authentication
  // ------------------------------------------------------------

  Future<AuthSession> login(String username, String password) async {
    final json = _object(
      await _request(
        'POST',
        '/api/auth/login',
        body: {'username': username, 'password': password},
      ),
      'login response',
    );
    return AuthSession.fromJson(json);
  }

  Future<AuthSession> signup(String username, String password) async {
    final json = _object(
      await _request(
        'POST',
        '/api/auth/signup',
        body: {'username': username, 'password': password},
      ),
      'signup response',
    );
    return AuthSession.fromJson(json);
  }

  Future<void> logout() async {
    await _request('POST', '/api/auth/logout');
  }

  Future<User> me() async {
    final json = _object(
      await _request('GET', '/api/auth/me'),
      'account response',
    );
    final user = json['user'];
    if (user is! Map<String, dynamic>) {
      throw const ApiException('The server returned an invalid account.');
    }
    return User.fromJson(user);
  }

  // ------------------------------------------------------------
  //  Recipes
  // ------------------------------------------------------------

  Future<int> healthRecipeCount() async {
    final json = _object(await _request('GET', '/api/health'), 'health check');
    final count = json['recipes'];
    return count is num ? count.toInt() : 0;
  }

  Future<List<Recipe>> listRecipes() async {
    return _list(
      await _request('GET', '/api/recipes'),
      'recipe list',
      Recipe.fromJson,
    );
  }

  Future<Recipe> getRecipe(int id) async {
    return Recipe.fromJson(
      _object(await _request('GET', '/api/recipes/$id'), 'recipe'),
    );
  }

  Future<Recipe> addRecipe(RecipeInput input) async {
    return Recipe.fromJson(
      _object(
        await _request('POST', '/api/recipes', body: input.toJson()),
        'created recipe',
      ),
    );
  }

  Future<Recipe> updateRecipe(int id, RecipeInput input) async {
    return Recipe.fromJson(
      _object(
        await _request('PUT', '/api/recipes/$id', body: input.toJson()),
        'updated recipe',
      ),
    );
  }

  Future<void> deleteRecipe(int id) async {
    await _request('DELETE', '/api/recipes/$id');
  }

  /// Rates a recipe. Pass [proofImageRef] only when the proof should change.
  /// An empty string deliberately removes the existing proof, matching API.md.
  Future<RatingSummary> rateRecipe(
    int id,
    int stars, {
    String? proofImageRef,
  }) async {
    final body = <String, dynamic>{'stars': stars};
    if (proofImageRef != null) body['proofImageRef'] = proofImageRef;

    return RatingSummary.fromJson(
      _object(
        await _request('PUT', '/api/recipes/$id/rating', body: body),
        'rating',
      ),
    );
  }

  Future<List<Recipe>> search(String query) async {
    final json = _object(
      await _request('GET', '/api/search', query: {'q': query}),
      'search response',
    );
    return _list(json['results'], 'search results', Recipe.fromJson);
  }

  /// Sends a free-form description to Gemini. Nothing is saved.
  Future<RecipeDraft> parseRecipe(String text) async {
    final json = _object(
      await _request(
        'POST',
        '/api/recipes/parse',
        body: {'text': text},
        timeout: _aiTimeout,
      ),
      'recipe draft',
    );
    return RecipeDraft.fromJson(json);
  }

  // ------------------------------------------------------------
  //  Photos
  // ------------------------------------------------------------

  /// Uploads a JPEG/PNG/WebP photo and returns its "/uploads/..." path.
  /// The server checks the file's magic bytes, not its name.
  Future<String> uploadImage(Uint8List bytes, String filename) async {
    final request = http.MultipartRequest('POST', _uri('/api/images'))
      ..headers['Accept'] = 'application/json'
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    _addAuth(request);

    http.Response response;
    try {
      final streamed = await _client.send(request).timeout(_requestTimeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException('The photo upload took too long.');
    } on SocketException {
      throw ApiException('Cannot reach the server at $baseUrl.');
    } on http.ClientException catch (error) {
      throw ApiException('The photo upload failed. ${error.message}');
    }

    dynamic decoded;
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          decoded is Map<String, dynamic> && decoded['error'] is String
          ? decoded['error'] as String
          : 'Photo upload failed (${response.statusCode}).';
      throw ApiException(message, statusCode: response.statusCode);
    }

    if (decoded is! Map<String, dynamic> || decoded['imageRef'] is! String) {
      throw const ApiException('The server returned an invalid photo path.');
    }
    return decoded['imageRef'] as String;
  }

  void dispose() {
    _client.close();
  }
}
