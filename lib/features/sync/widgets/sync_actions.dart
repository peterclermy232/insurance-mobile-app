import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../auth/screens/login_screen.dart';

/// Runs a sync and tells the officer what happened.
Future<void> syncWithFeedback(BuildContext context, {bool fullDownload = false}) async {
  final sync = context.read<SyncController>();
  final auth = context.read<AuthController>();
  if (auth.needsReauth) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen(reauth: true)));
    return;
  }
  final report = await sync.syncNow(fullDownload: fullDownload);
  if (report == null || !context.mounted) return;
  if (!report.ok) {
    final error = report.error;
    showMessage(
      context,
      error is AuthRequiredException
          ? 'Your session has expired. Sign in again to sync. Your records are safe on this device.'
          : '${report.summary} Your records are safe on this device.',
      error: true,
    );
    return;
  }
  showMessage(context, 'Sync complete: ${report.summary}.');
  if (report.notices.isNotEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Please note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final n in report.notices) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(n))],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }
}

/// Last sync time, pending counts and the "Sync now" button.
class SyncStatusCard extends StatelessWidget {
  const SyncStatusCard({super.key, this.onOpenDetails});

  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncController>();
    final theme = Theme.of(context);
    final waiting = sync.pendingCount + sync.pendingPhotos;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpenDetails,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.sync, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Sync', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              Text('Last sync: ${Fmt.relative(sync.lastSync)}', style: theme.textTheme.bodySmall),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _Stat(value: '${sync.pendingCount}', label: 'records to upload'),
              _Stat(value: '${sync.pendingPhotos}', label: 'photos to upload'),
              _Stat(
                value: '${sync.attentionCount}',
                label: 'need attention',
                color: sync.attentionCount > 0 ? theme.colorScheme.error : null,
              ),
            ]),
            const SizedBox(height: 12),
            if (sync.isSyncing) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(sync.progress ?? 'Syncing...', style: theme.textTheme.bodySmall),
            ] else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => syncWithFeedback(context),
                  icon: const Icon(Icons.sync),
                  label: Text(waiting > 0 ? 'Sync now ($waiting waiting)' : 'Sync now'),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
        Text(label, style: theme.textTheme.bodySmall),
      ]),
    );
  }
}
