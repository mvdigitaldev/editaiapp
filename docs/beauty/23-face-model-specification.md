# Face Model Specification — Warp Engine V3

Normativa para o Face Warp Engine V3 e o Anatomical Constraint Engine (ACE).
Gate obrigatório antes da implementação V3 (Sprint 32).

**Relacionado:** [`13-visual-quality-targets.md`](13-visual-quality-targets.md) (invariantes B1–B6), código em `lib/features/editor/beauty_engine/warp/anatomy/`.

## Princípios

1. **Uma topologia** — MediaPipe 478 landmarks + triangulação canônica (`face_mesh_topology.generated.dart`).
2. **Zonas anatômicas** — partição fina (`AnatomicalZone`), mais granular que `FaceWarpRegion`.
3. **Papel por vértice** — `rigid` | `semiRigid` | `free`.
4. **Intenção, não delta** — filtros emitem `AnatomicalIntent`; o ACE converte em Δv permitido.
5. **Composição linear única** — `Δv_total = ACE(Σ intent_i × f(intensity_i))`.
6. **Unidades** — deslocamentos em fração de **FSE** (face short edge px).

## Hierarquia de zonas

| Zona | Landmarks (subset) | Papel padrão |
|------|-------------------|--------------|
| `skullContour` | face oval MediaPipe | semiRigid |
| `forehead` | 9,10,151,337,… | free |
| `templeLeft` / `templeRight` | 127,162,21,54 / 356,389,251,284 | free |
| `browLeft` / `browRight` | 276,283,… / 46,53,… | semiRigid |
| `eyeLeft` / `eyeRight` | região olho + íris 468–477 | free |
| `noseRoot` | 168,6,197,195,5 | semiRigid |
| `noseDorsum` | 4,1,19,94,2,98,97 | free |
| `noseTip` | 1,4,5,275,440 | free |
| `noseAlae` | 326,327,294,278,… | free |
| `cheekLeft` / `cheekRight` | malar + cheekbone | free |
| `jawLeft` / `jawRight` | banda mandibular | free |
| `chin` | 152,175,199,200,17,18,… | free |
| `upperLip` / `lowerLip` | contorno externo | free |
| `mouthCorner` | 61,291,78,308 | free |
| `oralCavity` | inner mouth | **rigid** |
| `philtrum` | 0,37,267,164,393 | semiRigid |

Implementação: [`vertex_role_map.dart`](../lib/features/editor/beauty_engine/warp/anatomy/vertex_role_map.dart).

## Função de intensidade

```
raw = slider ∈ [0,1]
curve = easeOutCubic(raw)
quality = toolGate.intensityScale
effective = curve × quality
```

Famílias:
- **Escala** (olhos): `scale = 1 + k × easeOutCubic(raw)`
- **Deslocamento** (mandíbula): `disp = dMax × easeOutCubic(raw)`

## Anatomical Constraint Engine (ACE)

Ordem fixa de resolução:

1. Resolver zona → vértices via `AnatomicalZone`
2. Aplicar pins (rigid = 0; semi-rigid × peso de borda)
3. Combinar intents (prioridade ou média com clamp)
4. Clamp por ferramenta: |Δv| ≤ dMax × effective
5. Proporções naturais (olho-olho / boca dentro de [0.85, 1.15]× baseline)
6. Anti-fold (área tri < 35% original → rejeitar/scalar)
7. Simetria E/D quando `link_eyes` ou ferramenta bilateral
8. Emitir `ConstrainedVertexField` + log debug

Implementação prevista Sprint 32: `anatomical_constraint_engine.dart`.

## Especificação por ferramenta (22 filtros)

Tabelas completas em [`face_model_specification.dart`](../lib/features/editor/beauty_engine/warp/anatomy/face_model_specification.dart).

### Contorno e volume

| Tool | Zonas primárias | Δ max | Invariante |
|------|-----------------|-------|------------|
| `face_slim` | cheek, jaw | 8% FSE | B1 |
| `narrow_face` | cheek | 6% FSE | — |
| `v_face` | jaw, chin | 5% FSE | — |
| `jaw` | jaw | 7% FSE | B3 |
| `chin` | chin | 6% FSE | B4 |
| `cheekbone` | cheek | 5% FSE | — |
| `forehead` | forehead | 5% FSE | — |
| `temple` | temple | 4% FSE | — |
| `head_size` | skullContour | scale 1.0–1.12 | — |

### Nariz

| Tool | Zonas primárias | Δ max | Invariante |
|------|-----------------|-------|------------|
| `nose_slim` | alae, dorsum | 8% FSE | B2 |
| `nose_length` | dorsum, tip | 5% FSE | — |
| `nose_height` | root, dorsum | 4% FSE | — |
| `nose_tip` | tip | 5% FSE | — |
| `nose_bridge` | root, dorsum | 6% FSE | — |

### Olhos

| Tool | Zonas primárias | Δ max | Invariante |
|------|-----------------|-------|------------|
| `eye_scale` | eye L/R | scale 1.0–1.20 | B5 |
| `eye_distance` | eye L/R | 4% FSE | — |
| `eye_height` | eye L/R | 3% FSE | — |
| `eye_rotation` | eye L/R | 3° | — |
| `double_eyelid` | eye L/R | 2% FSE | — |

### Boca

| Tool | Zonas primárias | Δ max | Invariante |
|------|-----------------|-------|------------|
| `lip_thickness` | upper/lower lip | 6% FSE | B6 |
| `mouth_width` | corners + lips | 5% FSE | — |
| `smile` | corners, upper lip | 4% FSE | — |

## Critérios globais

- **Zero leakage:** |Δv| = 0 fora das zonas ativas + semi-rigid band
- **Pins imóveis:** rigid < 0.5 px @720p
- **Fundo:** pixels fora matte — Δ = 0
- **Monotonicidade:** slider ↑ não inverte direção
- **Fold:** nenhum triângulo < 35% área original
- **Multi-tool:** ACE resolve conflitos sem encolher centro

## Integração Tool Gate

[`ToolGateEngine`](../lib/features/editor/beauty_engine/tools/tool_gate_engine.dart) alimenta ACE com `intensityScale` **antes** do clamp anatômico.

## Sequência de implementação

| Sprint | Entregável |
|--------|------------|
| 31 | Este doc + tipos Dart + `face_model_spec_test.dart` |
| 32 | ACE + testes + debug viz vértices — **gate review** |
| 33+ | Face Warp Engine V3 sobre ACE |

## Gate Sprint 32

- [x] ACE implementado (`anatomical_constraint_engine.dart`)
- [x] Testes unitários ACE (`anatomical_constraint_engine_test.dart`)
- [x] Debug overlay vértices (rigid/semi/free) no lab
- [ ] Review Leonardo aprova tabelas → liberar Sprint 33
