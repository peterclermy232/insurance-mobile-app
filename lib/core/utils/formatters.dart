import 'package:intl/intl.dart';

class Fmt {
  Fmt._();

  static final _money = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 2);
  static final _date = DateFormat('d MMM yyyy');
  static final _dateTime = DateFormat('d MMM yyyy, HH:mm');
  static final _isoDate = DateFormat('yyyy-MM-dd');

  static String money(num? value) => value == null ? '-' : _money.format(value);

  static String date(DateTime? value) => value == null ? '-' : _date.format(value.toLocal());

  static String dateTime(DateTime? value) =>
      value == null ? '-' : _dateTime.format(value.toLocal());

  static String isoDate(DateTime value) => _isoDate.format(value);

  static DateTime? parse(String? value) =>
      (value == null || value.isEmpty) ? null : DateTime.tryParse(value);

  /// Human friendly "5 min ago" style for the last sync time.
  static String relative(DateTime? value, {DateTime? now}) {
    if (value == null) return 'Never';
    final diff = (now ?? DateTime.now()).difference(value.toLocal());
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return date(value);
  }

  static String coord(double? value) => value == null ? '-' : value.toStringAsFixed(6);

  /// Labels like "LOSS_ASSESSMENT" -> "Loss assessment".
  static String enumLabel(String? value) {
    if (value == null || value.isEmpty) return '-';
    final words = value.toLowerCase().replaceAll('_', ' ');
    return words[0].toUpperCase() + words.substring(1);
  }
}

double? toDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

/// Server record ids: random UUID strings, or numbers from servers and local
/// data that predate public ids. Always handled as opaque strings.
String? toServerId(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

int? toInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
