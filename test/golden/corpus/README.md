# Corpus de fotos — Golden Image Testing

Fotos reais usadas pela regressão visual da Beauty Engine (cap. 11 do plano
do SDK facial). **As fotos NÃO são commitadas** (pessoas reais, direito de
imagem) — cada máquina de teste/dev mantém a própria cópia local desta pasta.
Os testes que dependem do corpus são ignorados automaticamente quando as
fotos não existem (`loadCorpusEntries()` em `../golden_test_utils.dart`).

## Como montar o corpus (meta: 30–60 fotos)

Cobrir todas as combinações abaixo. Cada foto entra no `manifest.json` com
suas tags — a estratificação é usada nos relatórios (ex.: regressão só em
pele escura DEVE aparecer separada, não diluída na média).

- **Tom de pele (escala Fitzpatrick)**: I, II, III, IV, V, VI — mínimo 4
  fotos por estrato
- **Pose**: frontal, yaw ±15°, yaw ±30°, leve pitch
- **Iluminação**: estúdio/difusa, luz lateral dura, contraluz, baixa luz
- **Qualidade**: nítida (câmera nativa), levemente borrada, re-comprimida
  (ex.: recebida por WhatsApp), rosto pequeno no quadro (<300px)
- **Atributos**: óculos, barba, franja cobrindo testa, sorriso com dentes,
  boca fechada, brinco/colar, cabelo solto sobre o rosto
- **Formato**: incluir ao menos 2 fotos de iPhone (HEIC→JPEG Display P3) e
  2 com EXIF orientation ≠ 1 (retrato de câmera)

Requisitos: consentimento da pessoa fotografada para uso interno em testes;
resolução original (não redimensionar antes); manter o arquivo exatamente
como saiu da câmera/app (EXIF/ICC intactos — eles SÃO parte do teste).

## manifest.json

```json
{
  "photos": [
    {
      "id": "fitz3_frontal_estudio_01",
      "file": "photos/fitz3_frontal_estudio_01.jpg",
      "fitzpatrick": 3,
      "pose": "frontal",
      "lighting": "estudio",
      "quality": "nitida",
      "attributes": ["sorriso_dentes"]
    }
  ]
}
```

Coloque os arquivos em `photos/` (gitignored) e registre cada um no
manifesto. O `id` é usado como nome do golden derivado.
