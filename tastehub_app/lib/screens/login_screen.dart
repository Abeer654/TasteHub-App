// ============================================================
//  login_screen.dart - log in or create an account
//
//  TasteHub opens here when no saved session exists. The demo
//  accounts are one tap away so a live demo never needs typing.
// ============================================================

import 'package:flutter/material.dart';

import '../services/api_exception.dart';
import '../services/session_controller.dart';
import '../services/theme_controller.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.session,
    required this.themeController,
  });

  final SessionController session;
  final ThemeController themeController;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _signup = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_signup) {
        await widget.session.signup(_username.text.trim(), _password.text);
      } else {
        await widget.session.login(_username.text.trim(), _password.text);
      }
      // TasteHubApp listens to the session and swaps to the home screen.
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _demoLogin(String username, String password) async {
    _username.text = username;
    _password.text = password;
    await _submit();
  }

  void _toggleMode() {
    setState(() {
      _signup = !_signup;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colors.accent,
                    Color.lerp(colors.accent, colors.background, 0.55)!,
                    colors.background,
                  ],
                  stops: const [0, 0.42, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          // The wordmark stays one solid high-contrast colour
                          // here: the accent gradient behind it cannot carry a
                          // second accent tone at readable contrast in both
                          // modes. The home header uses the two-tone mark on
                          // its plain background.
                          RichText(
                            text: TextSpan(
                              style: Theme.of(context).textTheme.displaySmall
                                  ?.copyWith(color: colors.onAccent),
                              children: const [
                                TextSpan(text: 'Taste'),
                                TextSpan(text: 'Hub'),
                              ],
                            ),
                          ),
                          const Spacer(),
                          _ThemeMenu(
                            controller: widget.themeController,
                            onLight: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Home cooking, shared. Sign in to add recipes, rate '
                        'dishes and upload your own photos.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onAccent.withValues(alpha: 0.82),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildCard(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.line),
        boxShadow: [
          BoxShadow(
            color: colors.ink.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _signup ? 'Create your account' : 'Welcome back',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              _signup
                  ? 'Pick a username and a password with at least 6 characters.'
                  : 'Log in to keep your recipes and ratings separate.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _username,
              enabled: !_busy,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'junaid',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'Enter your username.';
                if (_signup && (text.length < 3 || text.length > 20)) {
                  return 'Use 3-20 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _busy ? null : _submit(),
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                ),
              ),
              validator: (value) {
                if ((value ?? '').isEmpty) return 'Enter your password.';
                if (_signup && (value ?? '').length < 6) {
                  return 'Use at least 6 characters.';
                }
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _ErrorNote(message: _error!),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: _busy
                  ? SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onAccent,
                      ),
                    )
                  : Icon(
                      _signup ? Icons.person_add_rounded : Icons.login_rounded,
                    ),
              label: Text(
                _busy
                    ? 'Please wait...'
                    : _signup
                    ? 'Create account'
                    : 'Log in',
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : _toggleMode,
              child: Text(
                _signup
                    ? 'Already have an account? Log in'
                    : 'New here? Create an account',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Divider(color: colors.line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'DEMO ACCOUNTS',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.muted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: colors.line)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _demoLogin('junaid', 'tastehub'),
                  icon: const Icon(Icons.person_rounded, size: 17),
                  label: const Text('junaid / tastehub'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _demoLogin('guest', 'guest'),
                  icon: const Icon(Icons.person_outline_rounded, size: 17),
                  label: const Text('guest / guest'),
                ),
                // The critic holds the community ratings that used to be
                // self-ratings (D-04), so authors still have numbers to show.
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _demoLogin('critic', 'critic'),
                  icon: const Icon(Icons.person_outline_rounded, size: 17),
                  label: const Text('critic / critic'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 19, color: colors.error),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeMenu extends StatelessWidget {
  const _ThemeMenu({required this.controller, this.onLight = false});

  final ThemeController controller;
  final bool onLight;

  @override
  Widget build(BuildContext context) {
    final colors = context.tasteHubColors;
    final foreground = onLight ? colors.onAccent : colors.ink;

    return PopupMenuButton<ThemeMode>(
      tooltip: 'Theme',
      initialValue: controller.mode,
      onSelected: controller.setMode,
      icon: Icon(Icons.brightness_6_rounded, color: foreground, size: 22),
      itemBuilder: (context) => const [
        PopupMenuItem(value: ThemeMode.system, child: Text('System theme')),
        PopupMenuItem(value: ThemeMode.light, child: Text('Light theme')),
        PopupMenuItem(value: ThemeMode.dark, child: Text('Dark theme')),
      ],
    );
  }
}
