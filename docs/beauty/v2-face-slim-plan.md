# Plano — Face Slim (Facial Warp V2)

**Estado:** spec congelada. Contrato: [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md). Template: [`v2-chin-plan.md`](./v2-chin-plan.md). Qualquer ponto que contradiga as regras é inválido.

Face Slim é o terceiro efeito. Reutiliza a pipeline já aprovada. Não modifica Jaw, Chin, renderer nem infra V2.

O Field produz **apenas** `DisplacementField`. Quem produz `WarpResult` é o renderer:

```text
FaceSlimField.build(...)
        ↓
DisplacementField

BackwardBilinearWarp.apply(...)
        ↓
WarpResult
```

`t = parameters['face_slim']` em `[0, 1]`. Sem face ou `t == 0`: identidade deste efeito.

---

## Pipeline alvo vs estado actual

**Alvo (arquitectura):** RGBA → Jaw → Chin → FaceSlim → Nose → Eyes → Mouth → Body → Skin → Color.

**Estado actual:** Jaw → Chin → Body → Skin → Color. Face Slim D **só** insere `applyFaceSlimWarp()` a seguir a `applyChinWarp()`. Não reordena Body/Skin/Color. Promoção da pipeline alvo = documento próprio.

Composição: chamadas sequenciais ao **mesmo** `BackwardBilinearWarp`. Sem mixer, `CompositeField`, `applyFaceWarp()`. Nenhum Field depende de outro Field V2. Cada Field é autocontido e constrói o seu `DisplacementField` apenas a partir de `FaceMeshResult`, `Size` e os seus próprios parâmetros. O renderer **não** recebe três campos ao mesmo tempo.

Produto (D/E), um efeito de cada vez:

```text
RGBA
   ↓
applyJawWarp()
   ↓
RGBA
   ↓
applyChinWarp()
   ↓
RGBA
   ↓
applyFaceSlimWarp()
   ↓
RGBA
```

---

## Contrato do Field

Recebe só: `FaceMeshResult`, `Size`, `double t`. Devolve `DisplacementField` (+ máscaras/métricas do módulo). Nunca RGBA, Texture, `WarpResult`, controller, preview.

---

## Template obrigatório

```
lib/.../warp/v2/face_slim/
    face_slim_field.dart
    face_slim_masks.dart
    face_slim_metrics.dart

test/beauty_engine/warp/v2/
    facial_warp_v2_face_slim_field_test.dart
    facial_warp_v2_face_slim_lab_test.dart

docs/beauty/
    v2-face-slim-a-report.md … v2-face-slim-e-report.md
```

Proibido `face_slim_utils`, `face_slim_helper`, Field no controller. Jaw e Chin **não** se relocalizam. Conjuntos de handles/hull vivem **no módulo** (não append em `region_catalog.dart`).

Isolamento (explícito):

- `face_slim_field.dart` **não importa** `jaw_field.dart`
- `face_slim_field.dart` **não importa** `chin_field.dart`
- O mesmo vale para `face_slim_masks.dart` e `face_slim_metrics.dart`
- Só lê o catálogo e as máscaras (`RegionMaskRaster` / máscaras próprias)
- IDs de domínio Jaw/Chin a proteger são constantes **locais** do módulo Face Slim (duplicar IDs, nunca importar o Field)

A regra geral “nenhum Field depende de outro Field V2” vive em [`FacialWarpV2-Development-Rules.md`](./FacialWarpV2-Development-Rules.md) §3.

---

## Objectivo geométrico

Afinar o **miolo da cara** (bochechas / mid-face) em Δx para a midline. **Não** é o Jaw (gônios) nem o Chin (mento).

Decisão de domínio (regra V2): Face Slim **não** desloca o domínio primário Jaw `{58, 288, 132, 361}` nem o mento Chin `{152}` / hull Chin. Se o efeito “só funcionar” mexendo gônios → **PARADA** + revisão arquitectural. Não se edita `JawField` / `ChinField` para compensar.

### Geometria inicial (Sprint A confirma ou redefine)

- Só **Δx** (dy = 0). Direcção: para a midline (`src = dest − d`).
- Os landmarks **123 / 352 são candidatos iniciais**. A Sprint A poderá redefinir os handles primários utilizando landmarks da região das bochechas (`leftCheek` / `rightCheek`) **sem alterar a arquitectura**.
- Secundários iniciais (peso menor): resto das bochechas, **sem** IDs Jaw/Chin — `{116, 147, 187, 207, 206, 203, 142, 126, 217, 345, 411, 425, 427, 436, 426, 423, 266, 371}`. Também ajustáveis na A.
- Hull activo inicial: união das bochechas acima. Sem `{58, 288, 132, 361, 172, 136, 365, 397, 152, 148, 176, 149, 377, 400, 378}`.
- Amplitude lab própria: `t * 0.04 * faceWidth`. Rampa + kernel (código **novo**; sem helpers extraídos de `jaw_field` / `chin_field`).

### Protecções hard-zero (Field Face Slim)

- Olhos, brows, nariz, boca, faceCenter, orelhas
- Domínio Jaw (primário + secundário) — IDs copiados no módulo Face Slim
- Domínio Chin `{152, 148, 176, 149, 377, 400, 378}`
- Fora do hull: `outsideSlimZone` = 0

### Métrica e gates

- Largura entre os handles primários **vigentes**: `slimWidthBefore` / `After`, `dx` em cada lado. `faceSlimNarrows` se a largura cai.
- `|dx|` nos primários na ordem de `influenceMax`. `|d|` em 58, 288 e 152 ≈ 0. Protecções p95 = 0. `minDetJ > 0`. Campo só Δx.
- Δ largura **suficiente para produzir redução visual perceptível**. O limiar numérico será calibrado durante a Sprint A. **Não** congelar um valor em px neste plano.
- **Gate de percepção (B/C):** o afinamento deve ser perceptível nas três imagens **p01, p05 e p12** no `v2Raw`. Caso contrário: **PARADA** e recalibração apenas do `FaceSlimField`. A Sprint A não substitui este gate. A Sprint A valida apenas o comportamento geométrico do Field e as suas métricas.

---

## Congelado (qualquer sprint)

`displacement_field.dart`, `backward_bilinear_warp.dart`, `jaw_field.dart`, módulo `chin/`, classe `RegionMasks`, `FieldMetrics`, testes de contrato V2.

Até C inclusive: sem controller, export, UI, Device Lab.

---

## Sprints (não fundir)

**A — Field.** Módulo + testes p01/p05/p12. Sem RGBA, sem renderer. Isolamento de imports: falhar se o fonte contiver `jaw_field.dart` ou `chin_field.dart`. A Sprint A valida apenas o comportamento geométrico do Field e as suas métricas. A percepção visual do resultado renderizado será validada definitivamente nas Sprints B (Lab) e C (sign-off). Relatório A inclui o limiar de Δ calibrado; não há sign-off visual oficial nesta sprint.

**B — Lab.** `FaceSlimField` + `BackwardBilinearWarp` só no teste. Matriz 3×3. Dumps `.cursor/facial-warp-v2/face-slim/B/`. Sem alterar `lib/`. Gate: afinamento visível nas 3 fotos no `v2Raw`.

**C — Visual.** Sign-off humano dos 9 `v2Raw`. Se não se vê afinamento em p01/p05/p12 → volta à A (só Field). Sem D sem C.

**D — Preview.** `applyFaceSlimWarp` (espelho de `applyChinWarp`). `_renderTexture`: Jaw → Chin → FaceSlim. Slider `'face_slim'` no Rosto. Sem mixer. Device Lab intocado.

**E — Export.** Não-tiled herda `_renderTexture`. Tiled: Face Slim no **frame inteiro** a seguir a Chin; tiles só body.

Regressão em toda sprint: `flutter test test/beauty_engine/warp/v2/`.

---

## Parada e rollback

**PARADA** se exigir: alterar renderer / `DisplacementField` / Jaw / Chin; fill/Telea; deslocar 58/288/152; preview antes da C; soma de Fields; ROI/MLS; importar `jaw_field.dart` ou `chin_field.dart`; métricas verdes sem afinamento visível em p01/p05/p12.

Rollback da Sprint A:

```text
rm -rf warp/v2/face_slim

+ apagar:

- testes Face Slim
- relatórios Face Slim

Diff esperado:

- renderer = vazio
- controller = vazio
- Jaw = vazio
- Chin = vazio
- infra = vazio
```

B: apagar teste lab e dumps `.cursor/facial-warp-v2/face-slim/B/`. `lib/` igual ao fim de A.
C: só relatório; nada a reverter no código.
D: remover `applyFaceSlimWarp` e a key `'face_slim'`. Jaw e Chin permanecem.
E: reverter só o tiled export; preview D pode ficar se E falhar sozinha.

---

## Fora de escopo

Relocar Jaw/Chin. Reordenar Body/Skin/Color. Nose / Eyes / Mouth. Device Lab. Mixer. Copiar MLS/`FaceSlimFilter` antigo. Fundir sprints.
