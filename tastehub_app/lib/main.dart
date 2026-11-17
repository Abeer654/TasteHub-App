import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'services/api_client.dart';
import 'services/session_controller.dart';
import 'services/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final api = ApiClient();
  final session = SessionController(api: api, prefs: prefs);
  final themeController = ThemeController(prefs: prefs);

  // Validate a saved token before the first frame. A stale token (for
  // example after the server's data was reset) falls back to the login screen.
  await session.restore();

  runApp(
    TasteHubApp(api: api, session: session, themeController: themeController),
  );
}
