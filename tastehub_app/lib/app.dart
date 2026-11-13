import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_client.dart';
import 'services/session_controller.dart';
import 'services/theme_controller.dart';
import 'theme.dart';

class TasteHubApp extends StatelessWidget {
  const TasteHubApp({
    super.key,
    required this.api,
    required this.session,
    required this.themeController,
  });

  final ApiClient api;
  final SessionController session;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([session, themeController]),
      builder: (context, _) {
        return MaterialApp(
          title: 'TasteHub',
          debugShowCheckedModeBanner: false,
          theme: buildTasteHubTheme(Brightness.light),
          darkTheme: buildTasteHubTheme(Brightness.dark),
          themeMode: themeController.mode,
          home: session.restoring
              ? _SplashScreen(colors: TasteHubColors.light)
              : session.isLoggedIn
              ? HomeScreen(
                  api: api,
                  session: session,
                  themeController: themeController,
                )
              : LoginScreen(session: session, themeController: themeController),
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({required this.colors});

  final TasteHubColors colors;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: colors.accent),
      ),
    );
  }
}
