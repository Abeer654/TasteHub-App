// H-06 / M-05: dish name -> placeholder food icon, with a generic fallback.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tastehub_app/widgets/recipe_thumbnail.dart';

void main() {
  group('dishIconFor', () {
    test('maps the demo dish names to their food icons', () {
      expect(dishIconFor('Chicken Biryani'), Icons.rice_bowl_rounded);
      expect(dishIconFor('Hydrabadi Pulao'), Icons.rice_bowl_rounded);
      expect(dishIconFor('Fried Fish'), Icons.set_meal_rounded);
      expect(dishIconFor('Crispy Fries'), Icons.fastfood_rounded);
      expect(dishIconFor('Loaded Cheese Fries'), Icons.fastfood_rounded);
      expect(dishIconFor('Beef Ramen'), Icons.ramen_dining_rounded);
      expect(dishIconFor('Chicken Tikka'), Icons.lunch_dining_rounded);
      expect(dishIconFor('Chocolate Cake'), Icons.cake_rounded);
    });

    test('is case-insensitive and falls back to generic cutlery', () {
      expect(dishIconFor('BIRYANI'), Icons.rice_bowl_rounded);
      expect(dishIconFor('  fried fish  '), Icons.set_meal_rounded);
      expect(dishIconFor('Mystery dish'), Icons.restaurant_rounded);
      expect(dishIconFor(''), Icons.restaurant_rounded);
    });
  });
}
