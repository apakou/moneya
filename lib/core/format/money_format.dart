import 'package:intl/intl.dart';

/// Money formatting helpers for MoneyA.
///
/// Centralises every numeric → display string conversion so that:
/// 1. Locale-correct grouping separators are used (`13,000` vs `13 000` vs
///    `13.000` depending on user locale).
/// 2. Decimal handling is consistent (whole numbers drop trailing zeros;
///    non-whole values render with exactly 2 decimals).
/// 3. We have a single seam to swap when amounts move from `String`/`double`
///    mock values to `Decimal`/`numeric(20,6)` once the backend lands.
///
/// Always pair the returned string with [AppTextStyles.tabular] so digits
/// align in vertical money columns (transactions list, receipt, review).
class MoneyFormat {
  MoneyFormat._();

  /// Formats a money amount supplied as a numeric string (mock-era).
  ///
  /// - `"13000"`  -> `"13,000"`
  /// - `"13000.5"` -> `"13,000.50"`
  /// - `""` / null / non-numeric -> input returned untouched (defensive).
  ///
  /// Pass [locale] (e.g. `'en_US'`, `'fr_FR'`) to override the device
  /// default. Defaults to the current platform locale.
  static String fromString(String? amount, {String? locale}) {
    if (amount == null || amount.isEmpty) return amount ?? '';
    final cleaned = amount.replaceAll(',', '').trim();
    final parsed = num.tryParse(cleaned);
    if (parsed == null) return amount;
    return fromNum(parsed, locale: locale);
  }

  /// Formats a numeric money amount.
  ///
  /// Whole numbers render without decimals (`13000` -> `13,000`); fractional
  /// values render with exactly 2 decimals (`13000.5` -> `13,000.50`).
  static String fromNum(num value, {String? locale}) {
    final isWhole = value == value.roundToDouble();
    final pattern = isWhole ? '#,##0' : '#,##0.00';
    return NumberFormat(pattern, locale).format(value);
  }
}
