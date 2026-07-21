# Sprint 27 — Release notes (App Store / Play Store)

**Versão:** 1.x (Beauty Engine)  
**Idioma:** PT-BR (adaptar EN para stores internacionais)

---

## Título sugerido (até 30 caracteres Play / 30 iOS)

**Retoque beauty profissional**

---

## O que há de novo

### Retoque beauty
- Novo fluxo **Retoque beauty** na Home e no Perfil
- **8 presets** prontos: Natural, Instagram, Influencer, Beauty, Wedding, Studio, Soft e Cinema
- Ajuste de rosto, corpo e pele com preview rápido
- Export em alta resolução, inclusive fotos 12MP+

### Presets personalizados
- Crie e salve seus próprios presets
- Sincronização na nuvem entre dispositivos (conta logada)
- **Marketplace**: publique e instale presets da comunidade

### Edição manual (já existente)
- Filtros, crop e ajustes sem IA — continua gratuito na Home

---

## Texto longo (descrição da atualização)

```
✨ Retoque beauty chegou ao Editai!

Aplique looks profissionais em um toque com presets otimizados para selfie e foto. Ajuste rosto, corpo e pele com preview instantâneo.

• 8 presets bundled inclusos
• Crie seus presets customizados
• Sync na nuvem + marketplace de presets
• Performance otimizada para fotos em alta resolução

Disponibilidade gradual: estamos liberando o retoque beauty para mais usuários a cada atualização. Se ainda não aparecer para você, aguarde — em breve!

Edição manual com filtros e recorte continua gratuita.
```

---

## Notas para revisão (Apple / Google)

- Beauty Engine usa **MediaPipe on-device** (face/pose) — sem envio de landmarks para servidores
- Processamento de imagem ocorre **localmente** no dispositivo
- Presets opcionais sincronizam via Supabase quando o usuário está logado
- Permissões: galeria/fotos para selecionar imagens (já existentes no app)

---

## Rollout operacional

| Fase | `beauty_engine_rollout_percent` | Público |
|------|----------------------------------|---------|
| 1 | 10 | Early adopters (~10%) |
| 2 | 50 | Metade dos usuários |
| 3 | 100 | Todos |

Ajustar em `app_settings` no Supabase Dashboard. Master switch: `beauty_engine_enabled` = `enable` | `disable`.

Monitorar tabela `beauty_engine_error_logs` por 7 dias pós-release.
