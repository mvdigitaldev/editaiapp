import 'package:intl/intl.dart';

import 'app_time_utils.dart';

/// Utilitario para parse e formatacao de datas vindas do servidor (Supabase/PostgreSQL).
/// O banco armazena em UTC (timestamptz). Este utilitario garante:
/// - Parse correto como UTC (adiciona Z se a string nao tiver timezone)
/// - Formatacao em horario de America/Sao_Paulo
class ServerDateUtils {
  ServerDateUtils._();

  /// Parse de data do servidor. Forca interpretacao UTC se a string nao tiver
  /// sufixo Z ou offset (+/-HH:MM). Retorna null se o valor for null ou invalido.
  static DateTime? parseServerDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    try {
      final hasTimezone = s.endsWith('Z') ||
          s.endsWith('z') ||
          RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
      final toParse = hasTimezone ? s : '${s}Z';
      return DateTime.parse(toParse);
    } catch (_) {
      return null;
    }
  }

  /// Parse que nunca retorna null. Usa [fallback] se o valor for invalido.
  static DateTime parseServerDateOr(dynamic v, DateTime fallback) {
    return parseServerDate(v) ?? fallback;
  }

  /// Formata [dt] para exibicao em horario do Brasil (America/Sao_Paulo).
  /// Retorna string vazia se [dt] for null.
  static String formatForDisplay(DateTime? dt,
      {String pattern = 'd MMM yyyy, HH:mm'}) {
    if (dt == null) return '';
    return DateFormat(pattern, 'pt_BR').format(AppTimeUtils.toBrazil(dt));
  }
}
