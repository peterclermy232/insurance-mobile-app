import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../location/location_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Captures a GPS point with accuracy and a retry button.
class GpsCapture extends StatefulWidget {
  const GpsCapture({
    super.key,
    required this.label,
    required this.onChanged,
    this.initial,
    this.autoCapture = false,
    this.required = false,
  });

  final String label;
  final GeoFix? initial;
  final ValueChanged<GeoFix?> onChanged;

  /// Start capturing as soon as the widget appears (e.g. new registrations).
  final bool autoCapture;
  final bool required;

  @override
  State<GpsCapture> createState() => GpsCaptureState();
}

class GpsCaptureState extends State<GpsCapture> {
  GeoFix? _fix;
  bool _busy = false;
  String? _error;

  GeoFix? get fix => _fix;

  @override
  void initState() {
    super.initState();
    _fix = widget.initial;
    if (widget.autoCapture && _fix == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => capture());
    }
  }

  Future<void> capture() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fix = await context.read<LocationService>().current();
      if (!mounted) return;
      setState(() => _fix = fix);
      widget.onChanged(fix);
    } on LocationFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not get a GPS fix. Retry in an open area.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fix = _fix;
    final missing = widget.required && fix == null && !_busy;
    final Color color = _error != null || missing
        ? AppTheme.danger
        : fix == null
            ? theme.colorScheme.onSurfaceVariant
            : (fix.isPoor ? AppTheme.warning : AppTheme.success);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.6)),
        color: theme.colorScheme.surface,
      ),
      child: Row(children: [
        Icon(fix == null ? Icons.location_searching : Icons.my_location, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.label + (widget.required ? ' *' : ''), style: theme.textTheme.labelLarge),
            const SizedBox(height: 2),
            if (_busy)
              const Text('Getting GPS fix...')
            else if (fix != null) ...[
              Text('${Fmt.coord(fix.latitude)}, ${Fmt.coord(fix.longitude)}'),
              Text(
                fix.isPoor ? 'Accuracy ${fix.accuracyLabel} (weak signal, retry if possible)' : 'Accuracy ${fix.accuracyLabel}',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ] else
              Text(_error ?? (missing ? 'Location is required' : 'Not captured'),
                  style: TextStyle(color: color, fontSize: 13)),
          ]),
        ),
        if (_busy)
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
        else
          TextButton.icon(
            onPressed: capture,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(fix == null ? 'Capture' : 'Retry'),
          ),
      ]),
    );
  }
}
