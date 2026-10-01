# Braços (Arms) — corpo V2

Key `arms`. Aba **Braços**, a última do Ajustar corpo (`corpo, pernas, curvas, bracos`). Livre, sem cadeado.

## Pedido

Leonardo, 2026-10-01: «agora vamos para o menu de braços.. esse menu deve mexer nos braços com o primeiro chamado arms: para o lado direito afina, e para o esquerdo aumenta. Outra vez, são movimentos naturais, nada exorbitante que desfaça as alterações que já temos aprovadas».

## Deformação

`BodyArmsField` (`warp/v2/body_arms/body_arms_field.dart`): Field V2 em CPU, só Δ perpendicular ao eixo de cada braço.

- **Eixo:** a polilinha ombro→cotovelo→pulso, `(11, 13, 15)` e `(12, 14, 16)`. Um braço só entra se tiver cotovelo e pulso visíveis e dentro da foto. Se nenhum braço servir, não há campo, o chip fica cinzento e o toque mostra «Falha ao reconhecer as linhas dos braços, não foi possível ajustar.».
- **Bordas pela `PersonMask`:** 32 amostras por segmento. Em cada uma procura-se a saída da máscara na normal, até `2,6 ×` a meia-largura estimada (era `1,7 ×`; braços cheios passam disso e ficavam presos) (`0,14 ×` a largura dos ombros no braço, `0,10 ×` no antebraço). Depois procura-se o vão até reentrar, até `saída + 4 × estimativa`.
- **Contacto:** se não houver saída, o braço está colado ao tronco desse lado. A borda fica na estimativa e o vão é 0. Como nas Pernas, cada lado abre com `smoothstep(vão / (0,8 · meia))` e a âncora fica na linha de contacto, `âncora = lo + (hi − lo) · aLo / (aLo + aHi)`. O braço solto escala em volta do centro, com as duas bordas a andar o mesmo. O braço colado escala em volta do contacto, e o tronco não se mexe.
- **Perfil:** dentro do braço o campo é `amp · (u − âncora)`. Fora dele cai em `min(0,55 · meia, 0,45 · vão)`, por isso nunca invade o tronco nem o outro lado do vão. Se o eixo não estiver dentro da máscara, a amostra não mexe.
- **Mistura dos segmentos:** o peso do antebraço é `smoothstep((d_braço − d_antebraço) / (2 · L) + 0,5)`, com `d` a distância ao segmento recortado e `L` a meia-largura média do braço (mínimo 4 px). O `s` ao longo do braço mistura-se com o mesmo peso. Nunca usar `1 / (d² + 1)²` em px: na prática ganha o segmento mais próximo e a bissectriz do cotovelo fica vincada, um degrau de 0,69 px por pixel. Os dois braços somam-se, porque não se tocam.
- **Faixa ao longo do braço:** sobe de `0,04` a `0,22` e desce de `0,80` a `0,94`. O ombro e a mão ficam parados.
- **Ganho `0,08`:** natural, menos que as Pernas (`0,12`). Num braço de 20 px cada borda anda cerca de 0,8 px no extremo do slider.
- **Sentido:** direita afina, esquerda engrossa.

## Cadeia

`waist → hips → legs → thighs → calves → arms`, cada um com o seu remap e medido na pose e na máscara originais. A trava de fundo cobre os Braços pelo `maxEdgeShift`. O slider só reescala o `BodyArmsFieldRuntime`, cuja chave é `identical(pose) && identical(mask) && size`.

## Testes

`test/beauty_engine/body_reshape/body_arms_field_test.dart`, numa cena com um braço esticado e outro pendurado e colado ao tronco:

- mede os dois braços na máscara;
- direita afina e esquerda engrossa (largura da coluna ±1 px);
- no braço solto, as duas bordas andam o mesmo (±15%, que é a precisão da borda na máscara), entre 0,4 e 1,2 px;
- no braço colado, o lado de contacto anda menos de 35% do lado livre e o tronco fica exactamente parado;
- a mão e o ombro ficam parados;
- `minDetJ > 0,5` nos dois extremos;
- braço levantado, cheio (meia-largura 25 px contra 14 px estimados) e dobrado a 90°, como na `body-p04`: a borda de fora anda mais de 1,2 px, e o degrau entre pixels vizinhos fica abaixo de 0,35 px, incluindo a bissectriz do cotovelo. Com os parâmetros antigos dava 0 px e 0,69 px;
- sem pulsos ou sem pose, fica indisponível;
- o slider só reescala o cache.

## Limites conhecidos

- No braço colado e inclinado, a linha de contacto real não se vê na máscara e usa-se a estimativa. O pixel junto ao tronco anda cerca de 0,2 px no extremo.
- Uma mão pousada no braço anda com ele.

## Calibração 2026-10-01 (body-p04)

Leonardo, com a modelo de braços para o alto: «não alterou muito.. talvez os pontos estão errados, e também deu uma serrilhada». Havia duas causas. A busca da borda (`1,7 ×` a estimativa) não chegava à borda de um braço cheio, por isso esse lado passava por encostado e o braço ficava parado. E a mistura `1/(d²+1)²` vincava a bissectriz do cotovelo. Corrigido com `exitReach = 2,6` e `elbowBlend = 1`. O ganho fica igual.
