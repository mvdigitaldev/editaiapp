# Visual Quality Targets — catálogo de fichas por ferramenta

Contrato de qualidade por ferramenta (cap. 19 do plano do SDK facial).
Sprint 0 cobre os Grupos A (pele) e B (warp) — 11 fichas. Grupos C
(regiões) e D (cor) entram nos Sprints 2 e 5.

Cada invariante mensurável vira asserção no golden testing
(`test/golden/`); cada regra de gating vira predicado no registry de
ferramentas (Sprint 3). Até lá, este documento é o critério de aceite das
comparações A/B no menu `/face-retouch-lab`.

Template:

- **Objetivo** — 1 frase
- **Targets** — o que DEVE acontecer (mensurável quando possível)
- **Invariantes** — o que NUNCA pode acontecer
- **Reduzir quando** — condições que aplicam cap na curva de intensidade
- **Desabilitar quando** — slider some/desativa com hint
- **Avisar quando** — ferramenta age, resultado potencialmente inferior

---

## Grupo A — Pele

### A1. Suavizar pele (`skin_smooth`)

- **Objetivo**: reduzir irregularidades de média frequência preservando
  textura de poros.
- **Targets**: variação local de baixa frequência da pele reduzida
  proporcionalmente ao slider; alta frequência preservada ≥70% no mix máximo.
- **Invariantes**: ΔE2000≈0 fora da máscara de pele (cílios, sobrancelha,
  cabelo, lábios, fundo intocados); sem halo na borda rosto/fundo; contraste
  local na pele não cai mais de 40% no slider máximo.
- **Reduzir quando**: blur alto (foto borrada já é "lisa"); ruído alto
  (smooth+ruído = plástico); rosto <200px.
- **Desabilitar quando**: máscara de pele indisponível E pose >45°
  (fallback geométrico não confiável).
- **Avisar quando**: rosto parcialmente ocluso (franja/mão) — resultado
  desigual entre os lados.

### A2. Remover acne/manchas (`remove_acne`)

- **Objetivo**: remover outliers locais (manchas, espinhas) sem apagar
  pintas intencionais nem textura saudável.
- **Targets**: mancha some na baixa frequência; poro sobre a área tratada
  permanece.
- **Invariantes**: nunca alterar >8% da área da máscara de pele por
  aplicação automática (mais que isso = está "lixando", não removendo
  pontos); ΔE2000≈0 fora da máscara de pele.
- **Reduzir quando**: compressão JPEG alta (blocking é confundível com
  mancha); ruído alto.
- **Desabilitar quando**: rosto <150px (mancha e poro indistinguíveis).
- **Avisar quando**: acne severa/aglomerada — sugerir pincel manual.

### A3. Remover olheiras (`remove_dark_circles`)

- **Objetivo**: clarear e neutralizar a região sob os olhos em direção ao
  tom da bochecha DO PRÓPRIO usuário (amostrado, nunca absoluto).
- **Targets**: L sobe em direção ao alvo amostrado; croma a/b converge para
  o tom da bochecha.
- **Invariantes**: não clarear além do tom da bochecha (senão vira máscara
  branca); transição suave sem borda visível na máscara; cílios inferiores
  intocados.
- **Reduzir quando**: sombra de iluminação dura (luz lateral) — parte da
  "olheira" é sombra legítima da cena; baixa luz geral.
- **Desabilitar quando**: óculos escuros/oclusão da região.
- **Avisar quando**: olheira muito escura + pele muito clara — resultado
  parcial em 1 passe.

### A4. Reduzir brilho/oleosidade (`skin_shine` — Fase 1)

- **Objetivo**: comprimir highlights especulares na pele sem apagar volume.
- **Targets**: highlights comprimidos em direção ao tom base amostrado;
  brilho de nariz/testa reduzido visivelmente a 50% do slider.
- **Invariantes**: brilho dos OLHOS e dos lábios intocado (não são
  oleosidade); pixels clipados (255) não inventam textura — reduzir, não
  reconstruir.
- **Reduzir quando**: exposição geral estourada (o problema é a foto, não a
  pele).
- **Desabilitar quando**: máscara de pele indisponível.
- **Avisar quando**: highlight clipado extenso — "não há informação para
  recuperar totalmente".

---

## Grupo B — Deformação (warp MLS)

### B1. Afinar rosto (`face_slim`)

- **Objetivo**: estreitar o contorno das bochechas/têmporas até ~15% da
  largura do rosto.
- **Targets**: contorno move para dentro simetricamente; pele interna
  acompanha sem esticar textura visivelmente.
- **Invariantes**: olhos, nariz e boca não se deslocam (landmarks dessas
  regiões imóveis, tolerância subpixel no golden); fundo atrás do contorno
  não "entorta" linha reta vertical mais que 1.5px no slider máximo; sem
  folding (guard anti-dobra ativo).
- **Reduzir quando**: yaw >20° (assimetria aparente amplifica — clamp já
  existente vira regra formal); rosto <200px.
- **Desabilitar quando**: contorno do rosto ocluso dos dois lados
  (cabelo/mãos) — landmarks de contorno com confiança baixa.
- **Avisar quando**: cabelo colado no contorno — a borda do cabelo
  acompanha o warp.

### B2. Afinar nariz (`nose_slim`)

- **Objetivo**: afinar até ~25% da largura sem afetar regiões vizinhas.
- **Targets**: largura das asas do nariz reduz proporcionalmente; dorso
  mantém forma.
- **Invariantes**: deslocamento zero fora do raio de influência (olhos,
  boca, bochechas imóveis no golden, tolerância subpixel); narinas movem
  simetricamente ao eixo do nariz; sem folding.
- **Reduzir quando**: yaw >20°; pitch acentuado (narinas viram a "frente"
  do nariz).
- **Desabilitar quando**: landmarks do nariz com confiança baixa (oclusão).
- **Avisar quando**: óculos apoiados no nariz — armação pode ondular
  levemente.

### B3. Mandíbula (`jaw`)

- **Objetivo**: afinar/definir a linha da mandíbula.
- **Targets**: banda do contorno jaw move para dentro com falloff suave até
  o pescoço.
- **Invariantes**: boca e queixo não deformam; sombra sob a mandíbula
  acompanha (não pode sobrar "sombra órfã" no lugar antigo); fundo com
  linhas retas não entorta >1.5px.
- **Reduzir quando**: barba volumosa (borda real da mandíbula incerta);
  yaw >25°.
- **Desabilitar quando**: mandíbula oclusa (mão no queixo, gola alta).
- **Avisar quando**: colar/gargantilha próximo — pode ondular.

### B4. Queixo (`chin`)

- **Objetivo**: alongar/encurtar ou afinar o queixo.
- **Targets**: ponta do queixo desloca no eixo vertical/horizontal
  configurado com falloff.
- **Invariantes**: lábio inferior não estica; linha da mandíbula conecta
  sem degrau; sem folding no vale queixo-pescoço.
- **Reduzir quando**: boca aberta (distância lábio-queixo é dinâmica);
  pitch acentuado.
- **Desabilitar quando**: queixo ocluso.
- **Avisar quando**: barba no queixo — textura pode esticar visivelmente.

### B5. Aumentar olhos (`eye_scale`)

- **Objetivo**: ampliar a região ocular até ~20% preservando anatomia.
- **Targets**: área do olho cresce uniformemente; ambos os olhos escalam
  igual com `link_eyes`.
- **Invariantes**: íris escala junto sem virar elipse (proteção existente —
  asserção: razão de aspecto da íris 1.0±2%); pálpebra e cílios acompanham
  sem dobra; sobrancelha desloca ≤20% do deslocamento do olho; specular da
  íris não estica.
- **Reduzir quando**: olhos semicerrados (ampliar olho quase fechado =
  artefato); yaw >25° (olho distante distorce mais).
- **Desabilitar quando**: olho ocluso (cabelo, óculos escuros).
- **Avisar quando**: óculos de grau — borda da lente pode ondular.

### B6. Lábios (`lip_thickness`)

- **Objetivo**: aumentar/reduzir o volume dos lábios até ~25%.
- **Targets**: contorno do lábio expande/contrai a partir da linha média da
  boca; arco do cupido preservado.
- **Invariantes**: dentes não deformam com boca aberta (região interna
  protegida); pele ao redor da boca desloca com falloff suave; comissuras
  não rasgam (sem folding).
- **Reduzir quando**: boca muito aberta (sorriso largo — contorno do lábio
  esticado); rosto pequeno.
- **Desabilitar quando**: boca oclusa (mão, objeto).
- **Avisar quando**: batom com contorno delineado — a borda pintada segue o
  warp, não a borda anatômica.

### B7. Sobrancelhas (`eyebrows` — posição/arco)

- **Objetivo**: elevar levemente ou ajustar o arco da sobrancelha.
- **Targets**: deslocamento vertical ≤8% da altura do rosto com falloff.
- **Invariantes**: pálpebra superior não estica junto além de 30% do
  deslocamento; testa acima não ondula; simetria E/D preservada quando
  ambas ativas.
- **Reduzir quando**: franja cobrindo sobrancelha (landmarks inferidos, não
  observados).
- **Desabilitar quando**: sobrancelhas totalmente oclusas.
- **Avisar quando**: sobrancelha muito fina/depilada — realce pode marcar
  borda dura.

---

## Uso nas comparações A/B (Sprint 0–6)

Ao comparar com o Banuba no menu `/face-retouch-lab`, avaliar cada
ferramenta pela ficha: cada invariante violado é bug (abrir issue com a
foto do corpus que reproduz); cada target não atingido no slider máximo é
tuning (Sprint 6). "Ficou bonito" sem ficha atendida não é critério de
aceite.
