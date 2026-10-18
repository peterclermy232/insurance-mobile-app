import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/utils/logger.dart';

/// Sign in. With [reauth] it is opened from the "Sign in again to sync"
/// banner and returns to the previous screen afterwards.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.reauth = false});

  final bool reauth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _slow = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final session = context.read<AuthController>().session;
    if (session != null) _username.text = session.email;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthController>();
    final sync = context.read<SyncController>();
    setState(() {
      _busy = true;
      _slow = false;
      _error = null;
    });
    // The hosted server may need ~50s to wake up.
    Future.delayed(AppConfig.slowServerHint, () {
      if (mounted && _busy) setState(() => _slow = true);
    });
    try {
      await auth.login(_username.text, _password.text);
      // First sign-in downloads everything; a re-login just catches up.
      sync.syncNow(fullDownload: !widget.reauth, trigger: 'login');
      if (widget.reauth && mounted) Navigator.of(context).pop();
    } on LoginRefused catch (e) {
      setState(() => _error = e.message);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e, st) {
      Log.e('Sign in failed', error: e, stackTrace: st, tag: 'auth');
      setState(() => _error = 'Sign in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = context.watch<ConnectivityService>().isOnline;
    return Scaffold(
      appBar: widget.reauth ? AppBar(title: const Text('Sign in to sync')) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (!widget.reauth) ...[
                    Icon(Icons.agriculture, size: 72, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(AppConfig.appName,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Ministry of Agriculture crop insurance programme',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 32),
                  ] else ...[
                    const Text('Your session has expired. Sign in again to upload your records. '
                        'Nothing captured on this device will be lost.'),
                    const SizedBox(height: 24),
                  ],
                  if (!online)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(children: [
                        Icon(Icons.cloud_off),
                        SizedBox(width: 12),
                        Expanded(child: Text('You are offline. Signing in needs an internet connection.')),
                      ]),
                    ),
                  TextFormField(
                    controller: _username,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email or username',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your email or username' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sign in'),
                  ),
                  if (_busy && _slow) ...[
                    const SizedBox(height: 12),
                    Text('Waking up the server. This can take up to a minute...',
                        textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
