// ============================================================
//  api_smoke.dart - check the app's API client against a live server
//
//  Usage:
//    dart run tool/api_smoke.dart http://127.0.0.1:8080
//
//  This is useful before a demo: it proves the app can log in, parse the
//  real list/detail/search responses, and group recipes by dish the same
//  way the home screen does.
// ============================================================

import 'dart:io';

import 'package:tastehub_app/services/api_client.dart';
import 'package:tastehub_app/services/api_exception.dart';
import 'package:tastehub_app/utils/ranking.dart';

Future<void> main(List<String> arguments) async {
  final baseUrl = arguments.isNotEmpty
      ? arguments.first
      : 'http://127.0.0.1:8080';
  final api = ApiClient(baseUrl: baseUrl);

  try {
    final count = await api.healthRecipeCount();
    stdout.writeln('health:     ok ($count recipes)');

    final session = await api.login('junaid', 'tastehub');
    api.token = session.token;
    stdout.writeln(
      'login:      ${session.user.username} (user ${session.user.id})',
    );

    final recipes = await api.listRecipes();
    stdout.writeln('recipes:    ${recipes.length}');

    if (recipes.isNotEmpty) {
      final detail = await api.getRecipe(recipes.first.id);
      stdout.writeln(
        'detail:     ${detail.title} '
        '(${detail.ingredients.length} ingredients, '
        '${detail.steps.length} steps)',
      );
    }

    final results = await api.search('briyani');
    stdout.writeln(
      'search:     ${results.length} result(s) for "briyani"'
      '${results.isEmpty ? '' : ' - first: ${results.first.title}'}',
    );

    final groups = groupRecipesByDish(recipes);
    stdout.writeln('dishes:     ${groups.length}');
    for (final group in groups.take(6)) {
      final top = group.topRecipe;
      final label = top == null
          ? 'empty'
          : top.isRated
          ? 'top ${top.title} ${top.averageRating.toStringAsFixed(1)}'
          : 'top ${top.title} (new)';
      stdout.writeln(
        '  ${group.name}: ${group.recipeCount} recipe(s), $label',
      );
    }

    await api.logout();
    stdout.writeln('\nApp API check passed for $baseUrl');
  } on ApiException catch (error) {
    stderr.writeln('FAIL: ${error.message}');
    exitCode = 1;
  } finally {
    api.dispose();
  }
}
