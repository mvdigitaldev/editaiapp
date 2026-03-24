import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/services/admin_catalog_image_upload.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/postgrest_user_message.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/categoria_model.dart';
import '../providers/modelos_provider.dart';

/// Formulário de criação/edição (apenas admins na UI; RLS no backend).
class AdminCategoriaFormPage extends ConsumerStatefulWidget {
  const AdminCategoriaFormPage({super.key});

  @override
  ConsumerState<AdminCategoriaFormPage> createState() =>
      _AdminCategoriaFormPageState();
}

class _AdminCategoriaFormPageState extends ConsumerState<AdminCategoriaFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  late final TextEditingController _slugController;
  late final TextEditingController _ordemController;
  bool _ativo = true;
  bool _saving = false;
  bool _pickingImage = false;
  bool _seededFromRoute = false;
  String? _coverImageUrl;

  CategoriaModel? get _existing {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    return args?['categoria'] as CategoriaModel?;
  }

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController();
    _slugController = TextEditingController();
    _ordemController = TextEditingController(text: '0');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seededFromRoute) return;
    _seededFromRoute = true;
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final existing = args?['categoria'] as CategoriaModel?;
    if (existing != null) {
      _nomeController.text = existing.nome;
      _slugController.text = existing.slug;
      _ordemController.text = '${existing.ordem}';
      _coverImageUrl = existing.coverImageUrl;
      _ativo = existing.ativo;
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _slugController.dispose();
    _ordemController.dispose();
    super.dispose();
  }

  String? _validateSlug(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Obrigatório';
    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(s)) {
      return 'Minúsculas, números e hífens (ex: minha-categoria)';
    }
    return null;
  }

  Future<void> _pickCoverImage() async {
    setState(() => _pickingImage = true);
    try {
      final client = ref.read(supabaseClientProvider);
      final url = await AdminCatalogImageUpload.pickAndUpload(
        client: client,
        bucket: AppConfig.thumbnailBucket,
      );
      if (!mounted) return;
      if (url != null) setState(() => _coverImageUrl = url);
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
    final ordem = int.tryParse(_ordemController.text.trim()) ?? 0;
    setState(() => _saving = true);
    try {
      final ds = ref.read(modelosDataSourceProvider);
      final existing = _existing;
      if (existing == null) {
        await ds.insertCategoria(
          nome: _nomeController.text.trim(),
          slug: _slugController.text.trim(),
          ordem: ordem,
          ativo: _ativo,
          coverImageUrl: _coverImageUrl,
        );
      } else {
        await ds.updateCategoria(
          existing.id,
          nome: _nomeController.text.trim(),
          slug: _slugController.text.trim(),
          ordem: ordem,
          ativo: _ativo,
          coverImageUrl: _coverImageUrl,
        );
      }
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
          existing == null ? 'Nova categoria' : 'Editar categoria',
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
            TextFormField(
              controller: _nomeController,
              decoration: const InputDecoration(labelText: 'Nome'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _slugController,
              decoration: const InputDecoration(
                labelText: 'Slug',
                hintText: 'ex: carros',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]')),
              ],
              validator: _validateSlug,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ordemController,
              decoration: const InputDecoration(labelText: 'Ordem'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 20),
            Text(
              'Imagem de capa',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textLight : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Envie uma imagem da galeria; a URL é preenchida automaticamente no banco.',
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
                child: _coverImageUrl != null && _coverImageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: _coverImageUrl!,
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
                    onPressed: (_saving || _pickingImage) ? null : _pickCoverImage,
                    icon: _pickingImage
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_outlined),
                    label: Text(
                      _coverImageUrl == null || _coverImageUrl!.isEmpty
                          ? 'Enviar imagem'
                          : 'Trocar imagem',
                    ),
                  ),
                ),
                if (_coverImageUrl != null && _coverImageUrl!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Remover imagem',
                    onPressed: (_saving || _pickingImage)
                        ? null
                        : () => setState(() => _coverImageUrl = null),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Ativa'),
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
