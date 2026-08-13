# Face Warp Engine — Fase 15 (MVP Foundation)

## Decisão congelada

Pipeline estrutural aprovado na Phase 14:

```
displacement → GlobalJacobianConstraint (ε=0.10) → GlobalJacobianSafetyGate → renderer
```

- **PASS:** displacement Phase 9
- **FAIL:** fallback para displacement original (pré-constraint)
- **Não alterar** a matemática em `experimental/global_jacobian_constraint.dart`

## Contrato numérico

| Constante | Valor | Arquivo |
|-----------|-------|---------|
| `phase9Epsilon` | `0.10` | `face_warp_numeric_contract.dart` |
| `numericTolerance` | `1e-6` | idem |
| `minimumAcceptedJacobian` | `epsilon - numericTolerance` | idem |

Pequenas diferenças de floating point próximas de ε **não** representam violação estrutural.

## Arquitetura

```
BeautyEditorPage (_params map persistente)
        ↓
BeautyEngineController.composeFaceField
        ↓
FaceMeshDeformationEngine
   ├─ AnatomicalIntentFactory (sliders → intents)
   ├─ ACE (pins, clamps, composição)
   └─ FaceWarpStructuralPipeline (Phase 9 + Safety Gate)
        ↓
FaceMeshForwardWarp / PassWarp (renderer)
```

### Abstração `FaceWarpOperation`

Cada ferramenta facial é uma operação configurável:

- `id` / `parameterKey` — chave do slider
- `spec` — região, pins, limites (`FaceModelSpecification`)
- `compositionMode` — `additive` (MVP rosto) ou `priority` (demais)

Registro MVP: `FaceWarpMvpOperations` (7 ferramentas de contorno).

### Composição multi-ferramenta

Sliders MVP usam **composição aditiva** no ACE — ao trocar de menu (ex.: Afinar 76% → Estreitar 80%), ambos os valores permanecem em `_params` e os deslocamentos **somam**, não se substituem.

Roteamento de render unificado via `FaceWarpVacancyFill.usesMvpMeshPath` — malha backward V3 para qualquer combinação MVP sem olhos/boca ativos.

## Como criar uma nova ferramenta facial

1. Adicionar spec em `face_model_specification.dart` (região, pins, `maxDisplacementFse`).
2. Implementar gerador de displacement em `pilot_warp_displacement.dart` ou filtro MLS legado.
3. Registrar em `FaceFilterPipeline.allFilters` e `faceWarpParameterKeys`.
4. Se for ferramenta MVP de rosto, incluir em `FaceWarpMvpOperations.parameterKeys`.
5. **Não** contornar `FaceWarpStructuralPipeline` — toda deformação V3 passa por Phase 9 + Safety Gate.
6. Adicionar testes em `test/beauty_engine/warp/face_warp_engine_test.dart`.

## Máscara e falloff

- **Região:** `FaceToolSpecification.primaryZones` / `freeZones`
- **Falloff:** pesos em `PilotWarpDisplacement` (ex.: `edgeWeight`, `zoneWeight`) e `GeometricSupport` no renderer
- **Influence map:** `FaceMatteRoi.buildInfluenceMap`

## Constraints e Safety Gate

- **ACE:** pins rígidos (olhos, nariz), clamps por FSE, composição
- **Phase 9:** `GlobalJacobianConstraint.apply` — solver Jacobi global (experimental, congelado)
- **Safety Gate:** `GlobalJacobianSafetyGate.validate` — critérios estruturais Phase 14

## Testes

```bash
flutter test test/beauty_engine/warp/face_warp_engine_test.dart
flutter test test/beauty_engine/warp/pass_warp_v3_isolation_test.dart
flutter run -t test/beauty_engine/warp/phase14_phase9_final_validation_main.dart -d <device>
```

## MVP rosto (menu Fase 15)

1. Afinar rosto (`face_slim`)
2. Estreitar rosto (`narrow_face`)
3. Rosto em V (`v_face`)
4. Mandíbula (`jaw`)
5. Queixo (`chin`)
6. Maçãs do rosto (`cheekbone`)
7. Testa (`forehead`)

**Fora do menu nesta fase:** têmporas, tamanho da cabeça (implementação permanece, UI removida).

## Fora de escopo (fases posteriores)

Nariz, olhos, boca, pele, cor — arquitetura preparada, não implementadas nesta fase.
