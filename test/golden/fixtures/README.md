# Fixtures de referência — Lab Nativo Beauty (Sprint 30)

Quatro fotos de referência para QA manual e goldens warp V3. **Não commitar
rostos reais** — cada dev mantém cópia local (mesmo padrão do
[`../corpus/README.md`](../corpus/README.md)).

## As 4 fotos obrigatórias

| ID | Perfil | Uso |
|----|--------|-----|
| `lab_frontal_adult` | Adulto frontal, luz difusa, rosto ≥400px FSE | Baseline B1–B6, A/B Banuba |
| `lab_profile_20deg` | Yaw ~20°, mesma pessoa ou similar | Gating yaw, assimetria |
| `lab_child_glasses` | Criança ou adulto com óculos largos | Oclusão ponte/temple |
| `lab_dark_skin` | Fitzpatrick V–VI, frontal | Contraste máscara pele/warp |

## Como capturar no device

1. Abrir `/face-retouch-lab` no app (flag `module_face_lab_enabled` ativa).
2. Selecionar foto da galeria — **sem crop**; manter EXIF/ICC originais.
3. Confirmar detecção facial (badge de ms verde/amarelo no canto).
4. Exportar original via share/debug ou copiar do path da galeria.
5. Renomear conforme tabela e colocar em `photos/` nesta pasta.
6. Registrar entrada em `manifest.json`.

Resolução mínima: 1080px na menor aresta. Preferir JPEG ou HEIC convertido
localmente sem recompressão agressiva.

## manifest.json

```json
{
  "fixtures": [
    {
      "id": "lab_frontal_adult",
      "file": "photos/lab_frontal_adult.jpg",
      "pose": "frontal",
      "notes": "baseline warp QA"
    },
    {
      "id": "lab_profile_20deg",
      "file": "photos/lab_profile_20deg.jpg",
      "pose": "yaw_20",
      "notes": "yaw gating"
    },
    {
      "id": "lab_child_glasses",
      "file": "photos/lab_child_glasses.jpg",
      "attributes": ["oculos"],
      "notes": "temple/nose bridge occlusion"
    },
    {
      "id": "lab_dark_skin",
      "file": "photos/lab_dark_skin.jpg",
      "fitzpatrick": 5,
      "notes": "skin mask contrast"
    }
  ]
}
```

## Fallback sintético (CI)

Quando as fotos locais não existem, os testes usam
[`../synthetic_portrait.dart`](../synthetic_portrait.dart) e
`test/beauty_engine/filters/skin/skin_face_fixture.dart`.

## Baseline de performance (Sprint 30)

Registrar no device mid-tier (tier B) com badge do lab:

- p50 e p95 de `total` no badge (após ~20 movimentos de slider)
- Log JSON: `beauty_benchmark` no console (debug builds)

Metas provisórias tier B: p50 ≤ 300 ms, p95 ≤ 600 ms no preview interativo.
