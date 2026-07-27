import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Encapsula speech-to-text para preencher prompts por voz.
class VoicePromptService {
  VoicePromptService({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  bool _initialized = false;
  bool _available = false;
  String? _preferredLocaleId;
  String? _lastInitError;

  bool get isAvailable => _available;
  bool get isListening => _speech.isListening;
  String? get lastInitError => _lastInitError;

  /// true em Simulator iOS (speech costuma falhar mesmo com permissão).
  static bool get isLikelySimulator {
    if (kIsWeb) return false;
    if (!Platform.isIOS) return false;
    // Heurística: simulators reportam "iPhone"/"iPad" sem "iPhone OS" hardware real
    // via environment; Flutter não expõe isso de forma estável, então usamos
    // um check via Platform.environment comum em sim.
    return Platform.environment.containsKey('SIMULATOR_DEVICE_NAME') ||
        Platform.environment.containsKey('SIMULATOR_UDID');
  }

  /// Inicializa o recognizer. [force] re-tenta mesmo após falha (ex.: permissão
  /// concedida depois).
  Future<bool> ensureInitialized({
    bool force = false,
    void Function(String status)? onStatus,
    void Function(String error)? onError,
  }) async {
    if (_initialized && !force) return _available;

    try {
      _available = await _speech.initialize(
        onStatus: (status) {
          debugPrint('[VoicePrompt] status: $status');
          onStatus?.call(status);
        },
        onError: (error) {
          debugPrint(
            '[VoicePrompt] error: ${error.errorMsg} permanent=${error.permanent}',
          );
          onError?.call(error.errorMsg);
        },
      );
      _lastInitError = _available ? null : 'initialize_unavailable';
      if (_available) {
        _preferredLocaleId = await _resolvePtBrLocale();
        debugPrint('[VoicePrompt] locale: $_preferredLocaleId');
      }
    } catch (e) {
      _available = false;
      _lastInitError = e.toString();
      debugPrint('[VoicePrompt] init exception: $e');
    }

    _initialized = true;
    return _available;
  }

  Future<String?> _resolvePtBrLocale() async {
    try {
      final locales = await _speech.locales();
      for (final locale in locales) {
        final id = locale.localeId.toLowerCase().replaceAll('-', '_');
        if (id == 'pt_br' || id.startsWith('pt_br')) {
          return locale.localeId;
        }
      }
      for (final locale in locales) {
        final id = locale.localeId.toLowerCase();
        if (id.startsWith('pt')) {
          return locale.localeId;
        }
      }
      if (locales.isNotEmpty) return locales.first.localeId;
    } catch (_) {}
    return null;
  }

  /// Mensagem amigável a partir do código de erro do plugin.
  static String friendlyError(String? raw) {
    final code = (raw ?? '').toLowerCase();

    if (isLikelySimulator) {
      return 'No Simulator o microfone/voz costuma falhar. '
          'Teste em um iPhone físico.';
    }

    if (code.contains('permission') || code.contains('not_allowed')) {
      return 'Permissão de microfone ou reconhecimento de fala negada. '
          'Ative em Ajustes > Editai.';
    }
    if (code.contains('network')) {
      return 'Sem conexão. O reconhecimento de voz precisa de internet '
          'neste dispositivo.';
    }
    if (code.contains('audio') || code.contains('microphone')) {
      return 'Não foi possível acessar o microfone. '
          'Feche outros apps que estejam usando o áudio e tente de novo.';
    }
    if (code.contains('language') || code.contains('locale')) {
      return 'Idioma de voz não suportado. Verifique se o português '
          'está instalado em Ajustes > Geral > Idioma e Região.';
    }
    if (code.contains('busy') || code.contains('client')) {
      return 'Reconhecimento ocupado. Aguarde um instante e tente de novo.';
    }
    if (code.contains('timeout') ||
        code.contains('no_match') ||
        code.contains('no_speech')) {
      return 'Não captamos fala. Fale mais perto do microfone e tente de novo.';
    }
    if (code.contains('initialize') || code.contains('unavailable')) {
      return 'Reconhecimento de voz indisponível neste dispositivo.';
    }

    return 'Não foi possível usar a voz agora. Tente de novo.';
  }

  /// Inicia escuta. [onResult] recebe o texto reconhecido e se é final.
  /// [onSoundLevel] recebe o nível em dB (tipicamente negativo no iOS).
  Future<bool> startListening({
    required void Function(String words, bool isFinal) onResult,
    void Function(String error)? onError,
    void Function(double levelDb)? onSoundLevel,
  }) async {
    final ready = await ensureInitialized(
      force: !_available,
      onError: onError,
    );
    if (!ready) {
      onError?.call(_lastInitError ?? 'initialize_unavailable');
      return false;
    }
    if (_speech.isListening) return true;

    try {
      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        onSoundLevelChange: onSoundLevel == null
            ? null
            : (level) {
                onSoundLevel(level);
              },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          // Erros transitórios (timeout/no_match) não devem matar a sessão
          // com mensagem de "permissão".
          cancelOnError: false,
          listenMode: ListenMode.confirmation,
          localeId: _preferredLocaleId,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 3),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[VoicePrompt] listen exception: $e');
      onError?.call(e.toString());
      return false;
    }
  }

  Future<void> stopListening() async {
    if (!_speech.isListening) return;
    try {
      await _speech.stop();
    } catch (_) {}
  }

  Future<void> cancelListening() async {
    try {
      await _speech.cancel();
    } catch (_) {}
  }

  void dispose() {
    if (_speech.isListening) {
      _speech.cancel();
    }
  }
}
