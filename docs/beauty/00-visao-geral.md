# Beauty Engine — Visão Geral

## Propósito

O **Beauty Engine** é um motor de edição facial e corporal **open source**, desacoplado da UI, projetado para evoluir o editaiapp até o nível de apps como CapCut, Meitu, BeautyCam, SNOW e Captions — **sem SDKs comerciais** (Tencent, Banuba, FaceUnity, IMG.LY).

## Relação com o Manual Editor

| Módulo | Entrega | Dependência |
|--------|---------|-------------|
| **Manual Editor** | **Primeira entrega** (Fase 1) | Independente |
| **Beauty Engine** | Roadmap pós-entrega (Sprints 01–27) | Reutilizável; **não depende** da UI do Manual Editor |

O Manual Editor continua exatamente como planejado:
- LUTs, crop, rotação, ajustes
- Persistência automática Supabase
- Edge Function `salvar-edicao-manual`
- `/comparison` + download
- Limites separados (`manual_edit`)

O Beauty Engine será integrado **depois**, como camada de processamento consumível por qualquer tela.

## Plataformas suportadas

O editaiapp é **nativo — somente iOS e Android**. Não há target Web, Desktop, Windows, macOS ou Linux.

Toda a stack (Manual Editor, Beauty Engine, MediaPipe, GPU) é projetada **exclusivamente** para:
- **Android** — OpenGL ES / Impeller / Vulkan (via runtime Android)
- **iOS** — Metal / Impeller

Não implementar fallbacks, degradations ou código condicional para Web/Desktop.

## Objetivos do Beauty Engine

1. **Detecção** — rosto (478 landmarks) e corpo (33 landmarks pose)
2. **Malha** — triangulação reutilizável para todos os efeitos
3. **Deformação** — warp MLS (extensível para TPS, ARAP, mesh warp)
4. **GPU** — renderização via Impeller + Metal (iOS) + OpenGL ES (Android); evitar CPU
5. **Presets** — LUT + beauty combinados; CRUD, import/export, sync Supabase
6. **Filtros** — roadmap completo face + body (ver `07-face-filters.md`, `08-body-filters.md`)

## Stack open source (obrigatória)

| Camada | Tecnologia |
|--------|------------|
| Face Mesh | MediaPipe Face Mesh (478 landmarks) |
| Pose | MediaPipe Pose (33 landmarks) |
| Warp | Moving Least Squares (MLS) → TPS / ARAP futuro |
| Color/LUT | flutter_image_filters + pipeline próprio |
| GPU | Flutter GPU / Impeller / fragment shaders |
| Bridge nativo | FFI ou platform channels para MediaPipe C++ |

## Documentação

| Doc | Conteúdo |
|-----|----------|
| [01-arquitetura.md](./01-arquitetura.md) | Camadas, desacoplamento, diagramas |
| [02-mediapipe.md](./02-mediapipe.md) | Face Mesh + Pose |
| [03-mesh.md](./03-mesh.md) | Mesh Engine |
| [04-warp.md](./04-warp.md) | Warp Engine |
| [05-render.md](./05-render.md) | GPU Rendering |
| [06-presets.md](./06-presets.md) | LUT + Beauty Presets |
| [07-face-filters.md](./07-face-filters.md) | Filtros faciais |
| [08-body-filters.md](./08-body-filters.md) | Filtros corporais |
| [09-performance.md](./09-performance.md) | Otimização |
| [10-roadmap.md](./10-roadmap.md) | Fases e dependências |
| [11-sprints.md](./11-sprints.md) | Sprints 01–27 detalhados |
| [adr/](./adr/) | Architecture Decision Records |
| [sprint-01-signoff.md](./sprint-01-signoff.md) | Sprint 01 concluída |

## Referência de produto

Apps alvo: CapCut, Meitu, BeautyCam, SNOW, Captions.

SDKs comerciais de referência (não usar): Tencent Beauty SDK, Banuba, FaceUnity.
