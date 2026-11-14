import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tastehub_app/services/theme_controller.dart';

Future<SharedPreferences> _prefs([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  test('defaults to the system theme', () async {
    final controller = ThemeController(prefs: await _prefs());

    expect(controller.mode, ThemeMode.system);
    expect(controller.label, 'System');
  });

  test('reads the saved mode', () async {
    final controller = ThemeController(
      prefs: await _prefs({ThemeController.modeKey: 'dark'}),
    );

    expect(controller.mode, ThemeMode.dark);
    expect(controller.label, 'Dark');
  });

  test('persists a mode change', () async {
    final prefs = await _prefs();
    final controller = ThemeController(prefs: prefs);

    await controller.setMode(ThemeMode.light);

    expect(controller.mode, ThemeMode.light);
    expect(prefs.getString(ThemeController.modeKey), 'light');

    final reopened = ThemeController(prefs: prefs);
    expect(reopened.mode, ThemeMode.light);
  });
}
