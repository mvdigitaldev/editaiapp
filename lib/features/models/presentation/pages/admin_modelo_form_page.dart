import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/services/admin_catalog_image_upload.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/postgrest_user_message.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/modelo_model.dart';
import '../providers/modelos_provider.dart';

/// Formulário de criação/edição de modelo (apenas admins na UI; RLS no backend).
class AdminModeloFormPage extends ConsumerStatefulWidget {
  const AdminModeloFormPage({super.key});

  @override
  ConsumerState<AdminModeloFormPage> createState() =>
      _AdminModeloFormPageState();
}

class _AdminModeloFormPageState extends ConsumerState<AdminModeloFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  late final TextEditingController _descricaoController;
  late final TextEditingController _promptController;
  late final TextEditingController _ordemController;
  bool _ativo = true;
  bool _saving = false;
  bool _pickingImage = false;
  bool _seededFromRoute = false;
  String? _categoriaId;
  String _categoriaNome = '';
  String? _thumbnailUrl;

  ModeloModel? get _existing {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return args?['modelo'] as ModeloModel?;
  }

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController();
    _descricaoController = TextEditingController();
    _promptController = TextEditingController();
    _ordemController = TextEditingController(text: '0');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seededFromRoute) return;
    _seededFromRoute = true;
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    _categoriaId = args?['categoriaId'] as String?;
    _categoriaNome = args?['categoriaNome'] as String? ?? '';
    final modelo = args?['modelo'] as ModeloModel?;
    if (modelo != null) {
      _nomeController.text = modelo.nome;
      _descricaoController.text = modelo.descricao ?? '';
      _promptController.text = modelo.promptPadrao ?? '';
      _ordemController.text = '${modelo.ordem}';
      _ativo = modelo.ativo;
      _thumbnailUrl = modelo.thumbnailUrl;
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _promptController.dispose();
    _ordemController.dispose();
    super.dispose();
  }

  Future<void> _pickThumbnail() async {
    setState(() => _pickingImage = true);
    try {
      final client = ref.read(supabaseClientProvider);
      final url = await AdminCatalogImageUpload.pickAndUpload(
        client: client,
        bucket: AppConfig.thumbnailBucket,
      );
      if (!mounted) return;
      if (url != null) setState(() => _thumbnailUrl = url);
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falha no envio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final categoriaId = _categoriaId;
    if (categoriaId == null || categoriaId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Categoria inválida.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final ordem = int.tryParse(_ordemController.text.trim()) ?? 0;
    setState(() => _saving = true);
    try {
      final ds = ref.read(modelosDataSourceProvider);
      final existing = _existing;
      final prompt = _promptController.text.trim();
      if (existing == null) {
        await ds.insertModelo(
          nome: _nomeController.text.trim(),
          descricao: _descricaoController.text.trim().isEmpty
              ? null
              : _descricaoController.text.trim(),
          categoriaId: categoriaId,
          thumbnailUrl: _thumbnailUrl,
          promptPadrao: prompt,
          ativo: _ativo,
          ordem: ordem,
        );
      } else {
        await ds.updateModelo(
          existing.id,
          nome: _nomeController.text.trim(),
          descricao: _descricaoController.text.trim().isEmpty
              ? null
              : _descricaoController.text.trim(),
          categoriaId: categoriaId,
          thumbnailUrl: _thumbnailUrl,
          promptPadrao: prompt,
          ativo: _ativo,
          ordem: ordem,
        );
      }
      ref.invalidate(modelosPorCategoriaProvider(categoriaId));
      ref.invalidate(categoriasProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(postgrestUserMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final existing = _existing;
    final cid = _categoriaId;

    if (cid == null || cid.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Erro'),
        ),
        body: const Center(child: Text('Categoria inválida.')),
      );
    }

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          color: isDark ? AppColors.textLight : AppColors.textPrimary,
        ),
        title: Text(
          existing == null ? 'Novo modelo' : 'Editar modelo',
          style: AppTextStyles.headingMedium.copyWith(
            color: isDark ? AppColors.textLight : AppColors.textPrimary,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _categoriaNome.isEmpty ? 'Categoria' : _categoriaNome,
              style: AppTextStyles.bodyMedium.copyWith(
                color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nomeController,
              decoration: const InputDecoration(labelText: 'Nome'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descricaoController,
              decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            Text(
              'Thumbnail',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textLight : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Envie uma imagem da galeria; a URL é salva automaticamente.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: isDark ? AppColors.textTertiary : AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _thumbnailUrl != null && _thumbnailUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: _thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => ColoredBox(
                          color: isDark
                              ? AppColors.surfaceDark
                              : AppColors.surfaceLight,
                        ),
                        errorWidget: (_, __, ___) => ColoredBox(
                          color: isDark
                              ? AppColors.surfaceDark
                              : AppColors.surfaceLight,
                          child: const Center(child: Icon(Icons.broken_image)),
                        ),
                      )
                    : ColoredBox(
                        color: isDark
                            ? AppColors.surfaceDark
                            : AppColors.surfaceLight,
                        child: Icon(
                          Icons.image_outlined,
                          size: 48,
                          color: AppColors.primary.withValues(alpha: 0.4),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_saving || _pickingImage) ? null : _pickThumbnail,
                    icon: _pickingImage
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_outlined),
                    label: Text(
                      _thumbnailUrl == null || _thumbnailUrl!.isEmpty
                          ? 'Enviar imagem'
                          : 'Trocar imagem',
                    ),
                  ),
                ),
                if (_thumbnailUrl != null && _thumbnailUrl!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Remover imagem',
                    onPressed: (_saving || _pickingImage)
                        ? null
                        : () => setState(() => _thumbnailUrl = null),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _promptController,
              decoration: const InputDecoration(
                labelText: 'Prompt padrão',
              ),
              maxLines: 5,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ordemController,
              decoration: const InputDecoration(labelText: 'Ordem'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Ativo'),
              value: _ativo,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _ativo = v),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
