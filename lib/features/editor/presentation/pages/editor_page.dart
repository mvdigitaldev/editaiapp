import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/image_preview.dart';
import '../widgets/effect_card.dart';

class EditorPage extends ConsumerWidget {
  final String? imagePath;

  const EditorPage({
    super.key,
    this.imagePath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor'),
      ),
      body: Column(
        children: [
          if (imagePath != null)
            Expanded(
              child: ImagePreview(imagePath: imagePath!),
            )
          else
            const Expanded(
              child: Center(
                child: Text('Selecione uma imagem para editar'),
              ),
            ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Efeitos de IA',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            height: 120,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: const [
                EffectCard(
                  effectType: 'ai_enhance',
                  title: 'Melhorar',
                  icon: Icons.auto_awesome,
                ),
                EffectCard(
                  effectType: 'ai_style',
                  title: 'Estilo',
                  icon: Icons.palette,
                ),
                EffectCard(
                  effectType: 'ai_background',
                  title: 'Fundo',
                  icon: Icons.landscape,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
