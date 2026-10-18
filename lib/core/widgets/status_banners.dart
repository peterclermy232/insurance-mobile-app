import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/auth/screens/login_screen.dart';
import '../auth/auth_controller.dart';
import '../network/connectivity_service.dart';
import '../theme/app_theme.dart';

/// Offline indicator and "sign in again to sync" banner, shown above content.
class StatusBanners extends StatelessWidget {
  const StatusBanners({super.key});

  @override
  Widget build(BuildContext context) {
    final online = context.watch<ConnectivityService>().isOnline;
    final needsReauth = context.watch<AuthController>().needsReauth;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (!online)
        const _Banner(
          color: Color(0xFF455A64),
          icon: Icons.cloud_off,
          text: 'Offline. Everything you capture is saved on this device and will sync later.',
        ),
      if (needsReauth)
        _Banner(
          color: AppTheme.warning,
          icon: Icons.lock_clock,
          text: 'Sign in again to sync. You can keep working offline.',
          action: TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginScreen(reauth: true)),
            ),
            child: const Text('SIGN IN'),
          ),
        ),
    ]);
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text, this.action});

  final Color color;
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, action == null ? 16 : 4, 8),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13))),
          if (action != null) action!,
        ]),
      ),
    );
  }
}
