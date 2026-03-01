import 'package:intl/intl.dart';

/// Utilitário para parse e formatação de datas vindas do servidor (Supabase/PostgreSQL).
/// O banco armazena em UTC (timestamptz). Este utilitário garante:
/// - Parse correto como UTC (adiciona Z se a string não tiver timezone)
/// - Formatação em horário local do dispositivo
class ServerDateUtils {
  ServerDateUtils._();

  /// Parse de data do servidor. Força interpretação UTC se a string não tiver
  /// sufixo Z ou offset (+/-HH:MM). Retorna null se o valor for null ou inválido.
  static DateTime? parseServerDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    try {
      // Se não termina com Z nem tem offset (+/-HH:MM), tratar como UTC
      final hasTimezone = s.endsWith('Z') ||
          s.endsWith('z') ||
          RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
      final toParse = hasTimezone ? s : '${s}Z';
      return DateTime.parse(toParse);
    } catch (_) {
      return null;
    }
  }

  /// Parse que nunca retorna null. Usa [fallback] se o valor for inválido.
  static DateTime parseServerDateOr(dynamic v, DateTime fallback) {
    return parseServerDate(v) ?? fallback;
  }

  /// Formata [dt] para exibição em horário local. Usa locale pt_BR.
  /// Retorna string vazia se [dt] for null.
  static String formatForDisplay(DateTime? dt, {String pattern = 'd MMM yyyy, HH:mm'}) {
    if (dt == null) return '';
    return DateFormat(pattern, 'pt_BR').format(dt.toLocal());
  }
}
