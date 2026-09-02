# V2 — Serrilhado na silhueta: a distância era L1

Data: 2026-09-02
Alcance autorizado por Leonardo, em dois passos escritos no mesmo dia:

1. **Transversal na distância**, nos seis Fields, incluindo V Chin (encerrado) e Cheekbones H («não alterar»).
2. **Reabrir o `jaw`** para trocar o `max` de gaussianas por crista em polilinha, mantendo amplitude `0.04`, Δx e energia nos gônios.

Amplitudes, hard-zeros e valores de slider: **intactos**. Nenhum outro efeito mudou de geometria.

---

## Sintoma

Leonardo, com **Mandíbula** (`jaw`) a 99%: serrilhado no bordo da silhueta, no ramo
entre a orelha e o gónio. Escada de pixel, não deformação errada.

---

## Diagnóstico

Duas causas independentes. O renderer está limpo: `BackwardBilinearWarp` é
bilinear puro e não introduz degraus. O defeito entra no campo.

### Causa 1 — `max` de gaussianas por landmark (só `jaw`) — **dominante, corrigida**

`jaw_field.dart` pesava a silhueta como `max` de gaussianas centradas em 8
landmarks discretos (`silhouettePrimary` a 1.0, `silhouetteSecondary` a 0.85),
σ = `0.08 × faceWidth`. O máximo de gaussianas isoladas ondula ao longo do bordo
— sobe em cada landmark, cai no vão — e na fronteira onde duas empatam a
derivada é descontínua.

Medido nos landmarks reais de p01/p05/p12, no ponto médio de cada vão contra as
âncoras que o limitam:

| Vão | Comprimento | σ | Peso no meio ÷ menor âncora |
|---|---|---|---|
| 132→58 (e 361→288) | 36–51 px | 23–30 px | **0.70 – 0.75** |
| 58→172 (e 288→397) | 29–45 px | 23–30 px | 0.90 – 0.97 |
| 172→136 (e 397→365) | 22–39 px | 23–30 px | 0.81 – 0.89 |

O vão 132→58 perdia **~30% do peso** ao longo de ~25 px de silhueta. Com
amplitude `0.04 × faceWidth` isso é uma ondulação de vários pixéis de
deslocamento no ramo orelha→gónio — exactamente onde Leonardo marcou o círculo.

É o mesmo defeito que este projecto já tinha resolvido no Cheekbones: *«`weight`
= distância à crista, **não** `max(gaussianas)`»*. O `jaw` era o último Field
com o padrão antigo.

**Correcção:** crista em polilinha, à imagem do Cheekbones e do V Shape.

```
curveLeft    = [132, 58, 172, 136]
curveRight   = [361, 288, 397, 365]
curveWeights = [0.85, 1.00, 0.90, 0.65]
sigmaAcrossFaceWidth = 0.08   (era handleSigmaFaceWidth, mesmo valor)
```

Ordem de cima para baixo: cauda junto à orelha → gónio → curva → cauda para o
mento. Não inverter: voltar atrás corta a crista. O peso interpola ao longo da
polilinha com pico no gónio, o que preserva «energia nos gônios 58–288». Um
ponto médio é inserido entre âncoras consecutivas para a distância ao segmento
não cortar em curvas fechadas. `amplitudeFaceWidth` continua `0.04`, o campo
continua só Δx e os gónios continuam a mandar.

No modelo novo o mesmo quociente do quadro acima é **1.06 – 1.19** em todos os
vãos e nas três faces: o meio do segmento nunca cava.

### Causa 2 — distância de Manhattan em passos inteiros — **corrigida**

A rampa de fronteira usava um chamfer de duas passagens com 4 vizinhos e custo
1. Isso mede em **L1**, não em euclidiana: as isolinhas saem em losango a 45° e
em valores inteiros. Como a silhueta mandibular é oblíqua, `boundary = dist /
falloff` subia em escada em vez de rampa. Cada degrau valia
`amplitude / falloff = (0.04 · fw) / (0.12 · fw) ≈ ⅓ px` de deslocamento — e ⅓ px
num bordo de contraste alto (pele contra cabelo escuro) é visível.

O mesmo chamfer estava copiado **sete** vezes: uma em cada um dos seis Fields e
outra em `RegionMaskRaster.dilate`. No `dilate` tinha um segundo efeito: um raio
`r` só dilatava `r / √2` na diagonal, pelo que o domínio activo nascia em
losango, com quinas a 45° que a rampa depois imprimia.

---

## Correcção

Novo módulo `warp/v2/distance_transform.dart`:
`EuclideanDistanceTransform`, transformada euclidiana **exacta** (Felzenszwalb &
Huttenlocher), separável, `O(width × height)`.

- `toZeroOf` — distância ao zero mais próximo (substitui `_distanceToInactive`).
- `toNonZeroOf` — distância ao não nulo mais próximo (substitui
  `_distanceToProtected` do Cheekbones e o chamfer do `dilate`).

As sete cópias do chamfer foram removidas. Ficheiros tocados na Causa 2:
`jaw_field.dart`, `jaw_angle/jaw_angle_field.dart`, `chin/chin_field.dart`,
`v_chin/v_chin_field.dart`, `v_shape/v_shape_field.dart`,
`cheekbones/cheekbones_field.dart`, `region_masks.dart`.

Não é um efeito novo nem uma Sprint. Não entra na cadeia nada de novo: é a mesma
rampa dos mesmos Fields, medida sem enviesamento direccional.

### Consequência assumida

O `dilate` passa a ser um disco em vez de losango, portanto o domínio activo
cresce nas diagonais até `r · (1 − 1/√2)` ≈ 29% de `r`. Isso é a intenção
declarada do pad («os gónios ficam no planalto, não na rampa») a funcionar de
forma isotrópica pela primeira vez. Afecta os seis efeitos de igual modo e
nenhuma métrica de lab saiu fora de tolerância.

---

## Verificação

- `facial_warp_v2_distance_transform_test.dart` — novo. Exactidão contra força
  bruta em máscara irregular, 3-4-5 (o L1 dava 7), semântica das duas sementes,
  1-Lipschitz sobre fronteira oblíqua (a rampa não pode ter degrau duplo),
  ausência de `NaN` sem sementes, guardas de tamanho.
- `facial_warp_v2_jaw_field_test.dart` — dois testes novos. **`t=1`** (o slider
  vai a 99% e o lab só cobria `t=0.5`): sem dobra e protecções mantidas nas três
  faces. **Anti-festão**: no ponto médio de cada vão da crista o `|dx|` tem de
  ficar ≥ 0.8 × a menor âncora. O limiar foi escolhido a partir da medição
  acima, portanto o teste **rejeita** o modelo antigo (0.70–0.75 no vão 132→58)
  e aceita o novo — não é um teste que passa sempre.
- `flutter test test/beauty_engine/` — **418 passam**. Inclui `minDetJ` dos seis
  efeitos (sem dobra em nenhuma face de benchmark), V Chin e Cheekbones H.
- `flutter analyze` — limpo nos ficheiros tocados.
- Custo, 1080×1440 em JIT: chamfer L1 18,6 ms, EDT 21,5 ms (**1,15×**). Em
  release AOT a diferença é menor. Os Fields com cache de peso unitário só
  pagam isto quando a geometria muda, não por movimento de slider.

---

## Passo 3 — a ponta no topo do ramo (mesmo dia, após ver a foto)

Leonardo, com o slider a 100%: a silhueta ficava **pontuda** na lateral do rosto,
à altura dos olhos. Pediu que a mandíbula puxe «100% da área da mandíbula e 5%
dessa área ali de fora, para não ter esse corte brutal».

Medido em `t=1`, o deslocamento ao longo da silhueta de cima para baixo era:

| | 127 | 234 | 93 | 132 | 58 |
|---|---|---|---|---|---|
| antes | 0.00 | **0.00** | **0.00** | 8.51 | 9.89 |
| agora | 0.00 | 0.51 | 2.12 | 8.55 | 9.89 |

O corte **não era da crista, era do domínio**: no 132 o campo valia 8.5 px e no
93, a 47 px de distância, valia zero, porque o pixel simplesmente saía do hull
do jaw. A rampa de fronteira só actua dentro do domínio, logo não havia
transição nenhuma — daí a ponta.

Três correcções, todas no `jaw_field.dart`:

1. **Cauda na crista.** `curveLeft` passou a `[234, 93, 132, 58, 172, 136]`
   (espelho `[454, 323, 361, 288, 397, 365]`) com pesos
   `[0.05, 0.20, 0.85, 1.00, 0.90, 0.65]`. Os dois primeiros levam peso baixo de
   propósito: é a cauda pedida, não é Cheekbones.
2. **Domínio estendido.** `taperLandmarks = {234, 93, 454, 323}` entram no hull.
   Sem isto o peso da cauda não tem onde actuar e a mudança não teria efeito.
3. **Pina fora da rampa longa.** O disco da orelha estava centrado em 323/454
   com raio `0.06 × faceWidth`. Mas **323/454 estão no oval, não na pina**: são
   a lateral do rosto, espelho de 93/234. O disco comia a silhueta e, pior,
   entrava na rampa de `0.12 × faceWidth`, o que deixava a cauda do lado direito
   a **um terço** do lado esquerdo (0.70 contra 2.12). Adoptado o esquema já
   validado no Cheekbones: raio `0.022`, pina deslocada `0.05` para fora do oval,
   e rampa própria `earFalloffFaceWidth = 0.035` separada da rampa do domínio.
   A cauda ficou 1.54 contra 2.12 — a assimetria que resta é a da própria pose.

A protecção da orelha mantém-se: `ears.p95Abs = 0` nas três faces.
`minDetJ` = 0.36–0.47 em `t=1`. `outsideJawZoneP95 = 0`.

Teste novo, `cauda na lateral do rosto é leve e simétrica`: exige a cauda entre
2% e 35% do pico no 93/323 e entre 0.5% e 15% no 234/454, e menos de 2× de
diferença entre os lados. Rejeita o estado anterior por ambos os motivos (era
0% no 93 e 3× de assimetria depois da cauda).

---

## O que mudou no resultado visual

Preencher os vãos aumenta a energia média ao longo da silhueta: o efeito fica
mais **uniforme** e um pouco menos concentrado nos picos dos landmarks. Era o
custo assumido ao autorizar a reabertura. A amplitude de pico não subiu
(`0.04 × faceWidth` intacta) e `minDetJ > 0` em `t=1` nas três faces.

Falta assinatura visual de Leonardo no editor. Enquanto isso, o `jaw` continua
**aprovado e vivo**; esta é uma correcção de qualidade de campo, não uma sprint
nova nem uma mudança de papel de produto.
