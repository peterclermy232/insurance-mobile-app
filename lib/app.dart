import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/auth/auth_controller.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/home/screens/home_screen.dart';

class CropInsuranceApp extends StatelessWidget {
  const CropInsuranceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.light,
      home: const AuthGate(),
    );
  }
}

/// Shows the login screen or the app depending on sign-in state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.select<AuthController, AuthStatus>((a) => a.status);
    return switch (status) {
      AuthStatus.loading => const _Splash(),
      AuthStatus.signedOut => const LoginScreen(),
      AuthStatus.signedIn => const HomeScreen(),
    };
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.primary,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.agriculture, size: 80, color: scheme.onPrimary),
          const SizedBox(height: 16),
          Text(AppConfig.appName,
              style: TextStyle(color: scheme.onPrimary, fontSize: 24, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
