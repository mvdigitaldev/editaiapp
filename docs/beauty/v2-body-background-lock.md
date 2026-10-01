# Body V2 — Travar fundo (`body_bg_lock`)

Estado: **no editor para inspecção visual** (2026-10-01). Só em Ajustar corpo e só para planos pagos activos.

Pedido do Leonardo: «crie um plano para colocar apenas para quem tem plano ativo pago, nao para os free.. apenas isso, acredito q n precisa mduar nad ano banco.. e faca apenas para a parte do corpo essa trava de fundo».

## O problema

Sem trava, o campo do corpo é um só para a pessoa e para o fundo. Para a cintura afinar, o fundo junto à borda estica na banda de queda: portas, azulejos e horizontes curvam. A trava faz o fundo ficar **parado**.

## Como funciona

Os Fields não mudam. A trava é uma composição no fim de `applyBodyWarpChain`:

1. **Alfa da pessoa (uma vez por foto):** a `PersonMask` amostrada no recorte, **binarizada no nível 0,5** e refinada por um guided filter sobre a luma (raio 2 px, `eps = 1e-3`). O guided filter só decide a ±1 px dessa borda (trimap); fora disso o alfa é 0 ou 1. A máscara do segmentador é confiança suave e ampliada, com uma rampa de vários px por cima do fundo: usada crua, todo esse halo contava como «meio pessoa», ficava acima de 0,04 e era arrastado (na `body-p02` a moldura da porta e a parede curvavam com a trava ligada; teste «máscara suave com halo largo», 220 níveis sem a binarização, ≤ 2 com ela). Sem o trimap, num fundo com textura forte, o guided filter copiava as arestas da luma e espalhava alfa de 0,15 a 0,35 até 3 px dentro do fundo, e esse fundo era arrastado com o corpo.
2. **Fundo limpo (uma vez por foto):** no recorte do suporte dos campos, preenche-se o fundo na **faixa de guarda** à volta da borda 0,5 e por dentro da pessoa até `bandPx = ceil(gain · maior meia-largura) + 6` px. Guarda: `max(3, ceil(2 × ampliação da máscara), round(0,004 × lado maior))` px. Só conta como fundo conhecido o que fica fora da guarda, porque a borda 0,5 erra alguns px: a roupa que passa da máscara, se fosse fundo conhecido, ficava parada ao afinar (fantasma da saia) e semeava o preenchimento. O preenchimento é **pull-push**: pirâmide de médias ponderadas dos pixels conhecidos, depois subida bilinear. A média anel a anel antiga arrastava raios de cor da borda para dentro do buraco, o que se via como «queimado» na cortina e na parede da `body-p02`.
3. **Remap:** cópia da origem com o alfa no canal A. O mesmo `BackwardBilinearWarp` deforma a cor e o alfa em conjunto, sem segundo remap. As fotos do editor são opacas, por isso o canal A está livre.
4. **Composição:** `out = rgb' + λ · (1 − a') · (fundo − rgb')`.
   - Onde a origem já era fundo seguro (fora da guarda), `λ = 1`: o pixel volta exactamente à origem.
   - Onde o fundo foi inventado, `λ = smoothstep(|D| / 0.25 px)`: onde o campo não mexe, a borda da pessoa fica como estava, sem costura no fim da faixa.
   - No fim, A volta a 255 em toda a imagem.

O cache (`BodyBackgroundLockRuntime`) usa a chave `identical(source) && identical(mask) && identical(fields) && tamanho && bandPx`. O campo da Cintura reutiliza a mesma instância de `DisplacementField` quando o slider muda, logo o fundo limpo é construído uma vez e o arrasto só paga o remap e a composição.

## Gate do plano

Sem mudanças no banco. Lê-se o que o utilizador já traz:

```dart
hasActivePaidPlan(subscriptionTier, subscriptionEndsAt)
  // tier != 'free' && (endsAt == null || endsAt > agora)
```

- `bodyBackgroundLockAllowedProvider` (`di/body_background_lock_access_provider.dart`) lê `authStateProvider`.
- `_gatedParams` no editor tira `body_bg_lock` (e as ferramentas pagas, como `thighs`) com `BodyWarpChain.gatePaidFeatures` quando não é pago ou não é `bodyOnly`. Corre antes do atalho de lab e pré-produção, e é o mesmo ponto para o preview e para o `_saveBodyEdit` (export).
- Na UI, a trava é uma **pílula sobre a foto**, centrada em baixo, como o «Bloqueio de fundo» do Meitu (`presentation/widgets/body_background_lock_pill.dart`): fundo preto a 62%, diamante rosa do plano pago, «Travar fundo» a 12,5 px e um switch de 34×20. Só aparece em Ajustar corpo, com foto e fora do modo pincel, e vale para todas as abas. Sem plano, o switch fica desligado e o toque abre uma folha com «Ver planos» → `/subscription`. Leonardo (2026-10-01): «troque agora so esse travar fundo, coloque igual no meitu, na imagem, mas pequeno e bonito». A linha antiga dentro do painel foi removida.
- O rosto não tem trava.

## Ficheiros

- `warp/v2/body_background/body_background_lock.dart`: `BodyBackgroundLock.prepare` / `packAlpha` / `composite`, `BodyBackgroundLockRuntime`, `BodyBackgroundLockPrepared`.
- `filters/body/body_warp_chain.dart`: `backgroundLockKey`, `backgroundLockRequested`, `gateBackgroundLock`. A trava sozinha não activa a cadeia.
- `controllers/beauty_engine_controller.dart`: `applyBodyWarpChain` (preview e export).
- `warp/v2/body_waist/body_waist_field.dart`: `maxEdgeShift` para o `bandPx`.
- `presentation/widgets/body_background_lock_pill.dart`: `BodyBackgroundLockPill`.
- `presentation/beauty_editor_page.dart`: gate em `_gatedParams`, a pílula no `Stack` da foto e `_showBackgroundLockPaywall`.

## Testes

`test/beauty_engine/body_reshape/body_background_lock_test.dart`, com tronco vermelho sobre riscas verticais azul/amarelo de 3 px:

- com trava, em `t = ±1`, o fundo a mais de 3 px da pessoa (na origem e no resultado) fica igual à origem com tolerância de 2 níveis;
- sem trava, as riscas junto à cintura deslocam-se;
- a largura da cintura afina o mesmo com e sem trava, com tolerância de ±1 px;
- o espaço que o corpo deixa não fica vermelho (sem halo);
- o fundo limpo constrói-se uma vez para três valores de slider;
- o canal A sai a 255.

`test/beauty_engine/body_reshape/body_background_lock_gate_test.dart`:

- `free`, tier nulo e plano vencido não têm trava; um plano pago com data futura ou sem data tem;
- `gateBackgroundLock` tira a chave e mantém o slider;
- pílula: altura ≤ 36 px; sem plano não liga e abre o aviso; com plano, o toque liga e desliga.

## Limites

- **O gate é do lado do cliente.** O processamento é local, sem custo de servidor, por isso é aceitável e dispensa o banco.
- **Preenchimento por camadas:** fica bom em fundos lisos e médios (`body-p01`, `body-p02`). Em linhas finas que cruzam a cintura (`body-p03`, `body-p04`) pode ficar borrado. PatchMatch fica para depois, se a inspecção o pedir.
- **Borda suave da pessoa:** até 3 px à volta da silhueta deformada há mistura legítima de pessoa e fundo (antialias). Não há estimativa da cor de primeiro plano (matting); se aparecer franja de cor, é o próximo passo.
- **Braço colado ao tronco:** com a trava, o braço é pessoa e acompanha o tronco, como sem ela.
