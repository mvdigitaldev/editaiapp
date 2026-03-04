class UtcDateRange {
  final DateTime start;
  final DateTime end;

  const UtcDateRange({
    required this.start,
    required this.end,
  });
}

/// Utilitario central para regras de horario do app.
///
/// Regra de negocio adotada:
/// - Banco permanece em UTC.
/// - Exibicao e calculos de periodo no app usam America/Sao_Paulo (UTC-3).
class AppTimeUtils {
  AppTimeUtils._();

  static const String brazilTimezone = 'America/Sao_Paulo';
  static const Duration _brazilOffset = Duration(hours: -3);

  static DateTime nowUtc() => DateTime.now().toUtc();

  static DateTime nowBrazil() => toBrazil(nowUtc());

  static DateTime toBrazil(DateTime dt) {
    final utc = dt.isUtc ? dt : dt.toUtc();
    return utc.add(_brazilOffset);
  }

  /// Converte uma data "local BRT" (ano/mes/dia/hora) para UTC.
  static DateTime brazilLocalToUtc({
    required int year,
    required int month,
    int day = 1,
    int hour = 0,
    int minute = 0,
    int second = 0,
  }) {
    final localAsUtc = DateTime.utc(year, month, day, hour, minute, second);
    return localAsUtc.subtract(_brazilOffset);
  }

  static UtcDateRange monthRangeBrazilToUtc(int year, int month) {
    final start = brazilLocalToUtc(year: year, month: month);
    final end = month == 12
        ? brazilLocalToUtc(year: year + 1, month: 1)
        : brazilLocalToUtc(year: year, month: month + 1);
    return UtcDateRange(start: start, end: end);
  }
}
