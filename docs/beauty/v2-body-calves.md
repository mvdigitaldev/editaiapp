# Canelas (Calves) — corpo V2

Key `calves`. Aba **Pernas**, depois das Coxas. **Só plano pago**: cadeado rosa no chip, `proParameterKeys = {thighs, calves}`, tirada por `gatePaidFeatures` em `_gatedParams` (preview e export). Sem plano, o toque abre «Ver planos».

## Pedido

Leonardo, 2026-10-01, com o Meitu Pernas → Calves: «agora criar a opção de mudar o tamanho das canelas.. não é algo exagerado, é algo natural.. só pode alterar quem pagar o plano pro, igual às coxas».

## Deformação

Sem Field novo: é o `BodyLegsField` das Pernas com a faixa `BodyLegBand.calves`.

- **Faixa relativa à canela** (`shinRelative`): `0` no joelho, `1` no tornozelo, na projecção de cada perna. Sobe de `−0,08` a `0,30`, que é uma cauda curta acima do joelho para não começar seco. Fica no máximo até `0,55`, a barriga da perna, e desce até `0,85`, antes do tornozelo. Coxa, tornozelo e pé ficam parados.
- **Escala:** cada perna escala em volta do seu centro, medido na máscara, por isso as duas bordas andam o mesmo. Como nas Pernas, coxas ou joelhos encostados ancoram na linha de contacto.
- **Ganho `0,07`:** natural. É pouco acima das Coxas (`0,06`) porque a canela é mais estreita. Numa canela de 40 px cada borda anda cerca de 1,4 px no extremo do slider.
- **Sentido:** direita afina, esquerda engrossa, como as Pernas e o Meitu.
- **Disponibilidade:** a mesma regra das Pernas (`requiresKnee`). Exige joelho na foto, tornozelo na foto ou canela à vista, e coxa de pelo menos `0,5 ×` o tronco. Sem isso o chip fica cinzento e o toque mostra «Falha ao reconhecer as linhas das pernas». Na `body-p02`, de saia e cortada acima do joelho, fica cinzento, como no Meitu.

## Cadeia

`waist → hips → legs → thighs → calves`. A trava de fundo cobre as Canelas pelo `maxEdgeShift` da faixa.

## Testes

Grupo «Canelas» em `test/beauty_engine/body_reshape/body_legs_field_test.dart`:

- coxa, tornozelo e pé parados;
- direita afina e esquerda engrossa;
- as duas bordas andam o mesmo, menos de 2 px;
- `minDetJ > 0.3` nos dois extremos;
- cache separado das Coxas.

Também: indisponível na foto cortada, e gate pago em `body_background_lock_gate_test.dart`.
