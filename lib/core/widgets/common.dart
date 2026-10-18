import 'package:flutter/material.dart';

import '../db/app_database.dart';
import '../db/syncable.dart';
import '../theme/app_theme.dart';

/// "Pending" / "Synced" / "Needs attention" chip for a record.
class SyncBadge extends StatelessWidget {
  const SyncBadge(this.sync, {super.key, this.compact = false});

  final SyncInfo sync;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (sync.status) {
      SyncStatus.synced => ('Synced', AppTheme.success, Icons.cloud_done_outlined),
      SyncStatus.error => ('Needs attention', AppTheme.danger, Icons.error_outline),
      SyncStatus.pendingParent => ('Waiting', AppTheme.warning, Icons.hourglass_empty),
      _ => ('Pending', AppTheme.warning, Icons.cloud_upload_outlined),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Explains a record's sync state in full (detail screens).
class SyncStateBanner extends StatelessWidget {
  const SyncStateBanner(this.sync, {super.key, this.notice, this.onRetry});

  final SyncInfo sync;
  final String? notice;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (sync.status == SyncStatus.error) {
      children.add(_Box(
        color: AppTheme.danger,
        icon: Icons.error_outline,
        title: 'The server could not accept this record',
        message: '${sync.error ?? 'Unknown error.'}\nCorrect the details and save to send it again.',
        action: onRetry == null ? null : TextButton(onPressed: onRetry, child: const Text('Retry as is')),
      ));
    } else if (sync.status == SyncStatus.pendingParent) {
      children.add(const _Box(
        color: AppTheme.warning,
        icon: Icons.hourglass_empty,
        title: 'Waiting for a linked record',
        message: 'This will upload after the farmer, farm or policy it belongs to has synced.',
      ));
    } else if (sync.status == SyncStatus.pending) {
      children.add(const _Box(
        color: AppTheme.warning,
        icon: Icons.cloud_upload_outlined,
        title: 'Saved on this device',
        message: 'It will be uploaded at the next sync.',
      ));
    }
    if (notice != null && notice!.isNotEmpty) {
      children.add(_Box(color: Colors.blueGrey, icon: Icons.info_outline, title: 'Note', message: notice!));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
    ]);
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.color, required this.icon, required this.title, required this.message, this.action});

  final Color color;
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            const SizedBox(height: 4),
            Text(message),
            if (action != null) Align(alignment: Alignment.centerRight, child: action),
          ]),
        ),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: theme.colorScheme.primary.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          if (message != null) ...[const SizedBox(height: 12), Text(message!)],
        ]),
      );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children, this.trailing, this.icon});

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 20, color: theme.colorScheme.primary), const SizedBox(width: 8)],
            Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 8),
          ...children,
        ]),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 130,
          child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        Expanded(child: Text((value == null || value!.isEmpty) ? '-' : value!, style: theme.textTheme.bodyMedium)),
      ]),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(border: Border.all(color: c.withOpacity(0.6)), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

Future<bool> confirm(BuildContext context,
    {required String title, required String message, String confirmLabel = 'Confirm', bool destructive = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppTheme.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppTheme.danger : null,
    ));
}

/// Reloads [load] whenever local data changes (edits or sync).
class DataBuilder<T> extends StatefulWidget {
  const DataBuilder({super.key, required this.changes, required this.load, required this.builder});

  final DataChanges changes;
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<DataBuilder<T>> createState() => _DataBuilderState<T>();
}

class _DataBuilderState<T> extends State<DataBuilder<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
    widget.changes.addListener(_reload);
  }

  @override
  void didUpdateWidget(covariant DataBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.changes != widget.changes) {
      oldWidget.changes.removeListener(_reload);
      widget.changes.addListener(_reload);
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = widget.load();
    });
  }

  /// Lets parents force a reload (e.g. search text changed).
  void reload() => _reload();

  @override
  void dispose() {
    widget.changes.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.warning_amber_outlined,
            title: 'Could not load data',
            message: '${snap.error}',
          );
        }
        if (!snap.hasData && snap.connectionState != ConnectionState.done) return const LoadingView();
        return widget.builder(context, snap.data as T);
      },
    );
  }
}
