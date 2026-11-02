/// A calendar date without a time or timezone.
///
/// POS expiry dates are stored in canonical `yyyy-MM-dd` form. The local
/// calendar date is captured before creating this value; no UTC conversion is
/// involved in expiry comparisons.
final class PosDate implements Comparable<PosDate> {
  const PosDate._(this.year, this.month, this.day);

  factory PosDate.fromParts(int year, int month, int day) {
    if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1) {
      throw FormatException('Invalid calendar date');
    }
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw FormatException('Invalid calendar date');
    }
    return PosDate._(year, month, day);
  }

  /// Captures the visible calendar fields of [value], whether local or UTC.
  factory PosDate.fromDateTime(DateTime value) =>
      PosDate.fromParts(value.year, value.month, value.day);

  /// Parses only a canonical, date-only `yyyy-MM-dd` value.
  factory PosDate.parse(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) throw FormatException('Expected yyyy-MM-dd');
    return PosDate.fromParts(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  /// Returns the current device-local calendar date used by the POS.
  factory PosDate.todayLocal([DateTime? now]) =>
      PosDate.fromDateTime(now ?? DateTime.now());

  final int year;
  final int month;
  final int day;

  String get isoDate => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// Expiry is inclusive: an item remains valid through its expiry date.
  bool isBefore(PosDate other) => compareTo(other) < 0;

  @override
  int compareTo(PosDate other) => isoDate.compareTo(other.isoDate);

  @override
  bool operator ==(Object other) =>
      other is PosDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => isoDate;
}
