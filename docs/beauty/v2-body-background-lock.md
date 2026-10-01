# Body V2 — Travar fundo (`body_bg_lock`)

Estado: **no editor para inspecção visual** (2026-10-01). Só em Ajustar corpo e só para planos pagos activos.

Pedido do Leonardo: «crie um plano para colocar apenas para quem tem plano ativo pago, nao para os free.. apenas isso, acredito q n precisa mduar nad ano banco.. e faca apenas para a parte do corpo essa trava de fundo».

## O problema

Sem trava, o campo do corpo é um só para a pessoa e para o fundo. Para a cintura afinar, o fundo junto à borda estica na banda de queda: portas, azulejos e horizontes curvam. A trava faz o fundo ficar **parado**.

## Como funciona

Os Fields não mudam. A trava é uma composição no fim de `applyBodyWarpChain`:

1. **Alfa da pessoa (uma vez por foto):** a `PersonMask` amostrada no recorte e refinada por um guided filter sobre a luma (raio 2 px, `eps = 1e-3`). O guided filter só decide a ±1 px da borda da máscara (trimap); fora disso o alfa é o da máscara, 0 ou 1. Sem o trimap, num fundo com textura forte, o guided filter copiava as arestas da luma e espalhava alfa de 0,15 a 0,35 até 3 px dentro do fundo, e esse fundo era arrastado com o corpo.
2. **Fundo limpo (uma vez por foto):** no recorte do suporte dos campos, preenche-se o fundo por dentro da pessoa, até `bandPx = ceil(gain · maior meia-largura) + 6` px. O preenchimento é por camadas, de fora para dentro: cada pixel recebe a média dos vizinhos 8-conexos já conhecidos. Depois uma caixa 3×3 só nos preenchidos tira o padrão dos anéis.
3. **Remap:** cópia da origem com o alfa no canal A. O mesmo `BackwardBilinearWarp` deforma a cor e o alfa em conjunto, sem segundo remap. As fotos do editor são opacas, por isso o canal A está livre.
4. **Composição:** `out = rgb' + λ · (1 − a') · (fundo − rgb')`.
   - Onde a origem já era fundo seguro, `λ = 1`: o pixel volta exactamente à origem.
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
- `_gatedParams` no editor tira `body_bg_lock` com `BodyWarpChain.gateBackgroundLock` quando não é pago ou não é `bodyOnly`. Corre antes do atalho de lab e pré-produção, e é o mesmo ponto para o preview e para o `_saveBodyEdit` (export).
- No painel, a linha «Travar fundo» com selo PRO só aparece na categoria corpo. Sem plano, o switch fica desligado e o toque abre uma folha com «Ver planos» → `/subscription`.
- O rosto não tem trava.

## Ficheiros

- `warp/v2/body_background/body_background_lock.dart`: `BodyBackgroundLock.prepare` / `packAlpha` / `composite`, `BodyBackgroundLockRuntime`, `BodyBackgroundLockPrepared`.
- `filters/body/body_warp_chain.dart`: `backgroundLockKey`, `backgroundLockRequested`, `gateBackgroundLock`. A trava sozinha não activa a cadeia.
- `controllers/beauty_engine_controller.dart`: `applyBodyWarpChain` (preview e export).
- `warp/v2/body_waist/body_waist_field.dart`: `maxEdgeShift` para o `bandPx`.
- `presentation/widgets/beauty_adjustments_panel.dart`: `_BackgroundLockRow`, `backgroundLockAllowed`, `onBackgroundLockLocked`.
- `presentation/beauty_editor_page.dart`: gate em `_gatedParams` e `_showBackgroundLockPaywall`.

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
- no painel, sem plano, o switch não liga e abre o aviso; com plano, grava a chave.

## Limites

- **O gate é do lado do cliente.** O processamento é local, sem custo de servidor, por isso é aceitável e dispensa o banco.
- **Preenchimento por camadas:** fica bom em fundos lisos e médios (`body-p01`, `body-p02`). Em linhas finas que cruzam a cintura (`body-p03`, `body-p04`) pode ficar borrado. PatchMatch fica para depois, se a inspecção o pedir.
- **Borda suave da pessoa:** até 3 px à volta da silhueta deformada há mistura legítima de pessoa e fundo (antialias). Não há estimativa da cor de primeiro plano (matting); se aparecer franja de cor, é o próximo passo.
- **Braço colado ao tronco:** com a trava, o braço é pessoa e acompanha o tronco, como sem ela.
