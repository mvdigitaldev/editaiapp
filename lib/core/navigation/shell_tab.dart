import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pedido de troca de aba do shell. O shell aplica o índice e volta a null.
final shellTabIndexProvider = StateProvider<int?>((ref) => null);
