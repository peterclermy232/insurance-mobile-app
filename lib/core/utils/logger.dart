import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Tiny logger that is silent in release builds.
class Log {
  Log._();

  static bool enabled = !kReleaseMode;

  static void d(String message, {String tag = 'app'}) {
    if (!enabled) return;
    developer.log(message, name: tag);
    debugPrint('[$tag] $message');
  }

  static void e(String message, {Object? error, StackTrace? stackTrace, String tag = 'app'}) {
    if (!enabled) return;
    developer.log(message, name: tag, error: error, stackTrace: stackTrace, level: 1000);
    debugPrint('[$tag] ERROR $message${error == null ? '' : ': $error'}');
    if (stackTrace != null) debugPrint('$stackTrace');
  }
}
