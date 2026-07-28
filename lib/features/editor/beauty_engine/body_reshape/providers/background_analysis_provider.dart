import '../../models/image_source.dart';
import '../models/background_analysis.dart';
import 'vision_capabilities.dart';

/// Análise estrutural do fundo (linhas/rigidez).
abstract class BackgroundAnalysisProvider {
  String get id;

  VisionCapabilities get capabilities;

  Future<BackgroundAnalysis?> analyze(ImageSource source);
}
