# Landmarks MediaPipe → regiões anatômicas

Inventário do mapeamento que **já existe no código**. Não cria grupos novos.

Relacionado: [`23-face-model-specification.md`](23-face-model-specification.md).

---

## 468 vs 478

| camada | contagem | índices | fonte |
|---|---|---|---|
| Tesselação Face Mesh | **468** | `0–467` | [`face_mesh_topology.generated.dart`](../../lib/features/editor/beauty_engine/mesh/face_mesh_topology.generated.dart) (`FaceMeshTopology.landmarkCount`) |
| Detecção com íris | **478** | `0–477` | [`face_mesh_result.dart`](../../lib/features/editor/beauty_engine/models/face_mesh_result.dart) (`expectedLandmarkCount`) |
| Íris | 10 | `468–472` olho esquerdo, `473–477` olho direito | [`face_warp_utils.dart`](../../lib/features/editor/beauty_engine/filters/face/face_warp_utils.dart) `irisLandmarkIndices` |

Os triângulos da malha cobrem só `0–467`. Os 10 pontos de íris entram nas zonas `eyeLeft` / `eyeRight` mas **não** na tesselação.

---

## Não é uma partição

Não existe uma lista “cada um dos 478 vértices pertence a exactamente um grupo”.

- As zonas são **subconjuntos sobrepostos** (ex.: `152` está em oval, jaw L/R e chin).
- **193** índices têm pelo menos um grupo nomeado.
- **285** vértices em `0–467` **não** estão em nenhuma `AnatomicalZone` nem nos grupos extra abaixo (miolo da malha, pálpebras internas, etc.). Continuam na triangulação; só não têm rótulo anatómico.

`jawRight` inclui `{323, 454}` (orelha / oval). Isso é o mapa MediaPipe do projeto, não um grupo “ear” formal (`AnatomicalZone` não tem ear). Ear experimental: `earLateral = {323, 454}`.

---

## Arquivos de mapeamento

| arquivo | o que contém |
|---|---|
| [`mesh_topology.dart`](../../lib/features/editor/beauty_engine/mesh/mesh_topology.dart) | `MeshTopology.faceRegionLandmarks`: oval, jaw L/R, nose, eyes, lips, cheeks, forehead (subsets dos 468) |
| [`face_mesh_topology.generated.dart`](../../lib/features/editor/beauty_engine/mesh/face_mesh_topology.generated.dart) | Triângulos canónicos MediaPipe (468 verts) |
| [`vertex_role_map.dart`](../../lib/features/editor/beauty_engine/warp/anatomy/vertex_role_map.dart) | `AnatomicalZone` → landmarks + papel `rigid/semiRigid/free` |
| [`anatomical_zone.dart`](../../lib/features/editor/beauty_engine/warp/anatomy/anatomical_zone.dart) | Enum das 22 zonas V3 |
| [`face_model_specification.dart`](../../lib/features/editor/beauty_engine/warp/anatomy/face_model_specification.dart) | Quais zonas cada ferramenta pode mover |
| [`face_warp_utils.dart`](../../lib/features/editor/beauty_engine/filters/face/face_warp_utils.dart) | Lábios, boca interna, cheekbone, íris, pálpebras, âncoras |
| [`face_warp_region.dart`](../../lib/features/editor/beauty_engine/filters/face/face_warp_region.dart) | Slider → região MLS grossa (`lowerFace`, `eyes`, …). **Não** é mapa por vértice |
| [`chin_landmark_audit.dart`](../../lib/features/editor/beauty_engine/warp/experimental/chin_landmark_audit.dart) | Tip/contour/jaw/gônio/oral protegida (experimental chin) |
| [`chin_g0_mls_field.dart`](../../lib/features/editor/beauty_engine/warp/experimental/chin_g0_mls_field.dart) | Handles G0 (mesmos IDs do audit) |
| [`chin_mesh_domain_catalog.dart`](../../lib/features/editor/beauty_engine/warp/experimental/chin_mesh_domain_catalog.dart) | `earLateral`, núcleos E0/F |

Não há ficheiro de máscara bitmap por vértice. Máscaras de pele (`skin_soft_region.dart`) são elipses 2D na imagem, não IDs MediaPipe.

---

## `AnatomicalZone` (produção V3)

Fonte: `VertexRoleMap`. Papel = `defaultRole`.

| zona | papel | IDs |
|---|---|---|
| `skullContour` | semiRigid | `10, 21, 54, 58, 67, 93, 103, 109, 127, 132, 136, 148, 149, 150, 152, 162, 172, 176, 234, 251, 284, 288, 297, 323, 332, 338, 356, 361, 365, 377, 378, 379, 389, 397, 400, 454` |
| `forehead` | free | `9, 10, 21, 54, 67, 103, 109, 151, 297, 332, 337, 338` |
| `templeLeft` | free | `21, 54, 67, 103, 109, 127, 162` |
| `templeRight` | free | `251, 284, 297, 332, 338, 356, 389` |
| `browLeft` | semiRigid | `276, 282, 283, 285, 293, 295, 296, 300, 334, 336` |
| `browRight` | semiRigid | `46, 52, 53, 55, 63, 65, 66, 70, 105, 107` |
| `eyeLeft` | free | tesselação `{249, 263, 362, 373, 374, 380, 381, 382, 384, 385, 386, 387, 388, 390, 398, 466}` + íris `{468, 469, 470, 471, 472}` |
| `eyeRight` | free | tesselação `{7, 33, 133, 144, 145, 153, 154, 155, 157, 158, 159, 160, 161, 163, 173, 246}` + íris `{473, 474, 475, 476, 477}` |
| `noseRoot` | semiRigid | `5, 6, 168, 195, 197` |
| `noseDorsum` | free | `1, 2, 4, 19, 94, 97, 98` |
| `noseTip` | free | `1, 4, 5, 275, 440` |
| `noseAlae` | free | `45, 48, 64, 115, 220, 278, 294, 326, 327, 344` |
| `cheekLeft` | free | `116, 123, 126, 142, 147, 187, 203, 206, 207, 217` |
| `cheekRight` | free | `266, 345, 352, 371, 411, 423, 425, 426, 427, 436` |
| `jawLeft` | free | `58, 132, 136, 148, 149, 150, 152, 172, 176, 377` |
| `jawRight` | free | `152, 288, 323, 361, 365, 378, 379, 397, 400, 454` |
| `chin` | free | `17, 18, 148, 149, 150, 152, 175, 176, 199, 200` |
| `upperLip` | free | `0, 37, 39, 40, 185, 267, 269, 270, 409` |
| `lowerLip` | free | `17, 84, 91, 146, 181, 314, 321, 375, 405` |
| `mouthCorner` | free | `61, 78, 291, 308` |
| `oralCavity` | **rigid** | `13, 14, 80, 81, 82, 87, 88, 178, 191, 310, 311, 312, 317, 318, 324, 402, 415` |
| `philtrum` | semiRigid | `0, 37, 164, 267, 393` |

Pálpebras extra (não são `AnatomicalZone`): `upperEyelidLeft = {362, 384, 385, 386, 398, 466}`, `upperEyelidRight = {133, 157, 158, 159, 173, 246}`.

---

## Grupos chin (experimental; não produção)

Mesmos IDs em `ChinLandmarkAudit` / `ChinG0MlsField`.

| grupo | IDs | handle? |
|---|---|---|
| TIP | `152` | sim |
| CONTOUR | `148, 149, 150, 176, 377, 378, 379, 400` | sim |
| JAW | `136, 172, 365, 397` | sim |
| observacionais | `175, 199, 200` | não |
| gônio | `58, 288, 132, 361` | não |
| interior submental | `171, 396` | não |
| labiomental | `18, 313, 421, 428` | pin oral |
| oval inferior (ordem) | `132, 58, 172, 136, 150, 149, 176, 148, 152, 377, 400, 378, 379, 365, 397, 288, 361` | — |
| `protectedOral` | lábios + cavidade + cantos + labiomental (**43** IDs) | `δ=0` |
| `earLateral` | `323, 454` | métrica leak |

`protectedOral` expandido: `0, 13, 14, 17, 18, 37, 39, 40, 61, 78, 80, 81, 82, 84, 87, 88, 91, 146, 178, 181, 185, 191, 267, 269, 270, 291, 308, 310, 311, 312, 313, 314, 317, 318, 321, 324, 375, 402, 405, 409, 415, 421, 428`.

---

## `FaceWarpRegion` (sliders, não vértices)

| região | parâmetros |
|---|---|
| `lowerFace` | jaw, chin, v_face, face_slim |
| `midFace` | nose_* |
| `eyes` | eye_* , double_eyelid |
| `mouth` | mouth_width, lip_thickness, smile |
| `cheek` | cheekbone, narrow_face |
| `contour` | forehead, temple, head_size |

---

## Lista 0–477

Coluna **Zonas V3** = `AnatomicalZone`. Coluna **Extra** = íris, oral protegida, handles chin, gônio, orelha. `—` = sem grupo nomeado.

| id | Zonas V3 | Extra |
|---:|---|---|
| 0 | upperLip, philtrum | protectedOral |
| 1 | noseDorsum, noseTip | — |
| 2 | noseDorsum | — |
| 3 | — | — |
| 4 | noseDorsum, noseTip | — |
| 5 | noseRoot, noseTip | — |
| 6 | noseRoot | — |
| 7 | eyeRight | — |
| 8 | — | — |
| 9 | forehead | — |
| 10 | skullContour, forehead | — |
| 11 | — | — |
| 12 | — | — |
| 13 | oralCavity | protectedOral |
| 14 | oralCavity | protectedOral |
| 15 | — | — |
| 16 | — | — |
| 17 | chin, lowerLip | protectedOral |
| 18 | chin | protectedOral, labiomental |
| 19 | noseDorsum | — |
| 20 | — | — |
| 21 | skullContour, forehead, templeLeft | — |
| 22 | — | — |
| 23 | — | — |
| 24 | — | — |
| 25 | — | — |
| 26 | — | — |
| 27 | — | — |
| 28 | — | — |
| 29 | — | — |
| 30 | — | — |
| 31 | — | — |
| 32 | — | — |
| 33 | eyeRight | — |
| 34 | — | — |
| 35 | — | — |
| 36 | — | — |
| 37 | upperLip, philtrum | protectedOral |
| 38 | — | — |
| 39 | upperLip | protectedOral |
| 40 | upperLip | protectedOral |
| 41 | — | — |
| 42 | — | — |
| 43 | — | — |
| 44 | — | — |
| 45 | noseAlae | — |
| 46 | browRight | — |
| 47 | — | — |
| 48 | noseAlae | — |
| 49 | — | — |
| 50 | — | — |
| 51 | — | — |
| 52 | browRight | — |
| 53 | browRight | — |
| 54 | skullContour, forehead, templeLeft | — |
| 55 | browRight | — |
| 56 | — | — |
| 57 | — | — |
| 58 | skullContour, jawLeft | gonion |
| 59 | — | — |
| 60 | — | — |
| 61 | mouthCorner | protectedOral |
| 62 | — | — |
| 63 | browRight | — |
| 64 | noseAlae | — |
| 65 | browRight | — |
| 66 | browRight | — |
| 67 | skullContour, forehead, templeLeft | — |
| 68 | — | — |
| 69 | — | — |
| 70 | browRight | — |
| 71 | — | — |
| 72 | — | — |
| 73 | — | — |
| 74 | — | — |
| 75 | — | — |
| 76 | — | — |
| 77 | — | — |
| 78 | mouthCorner | protectedOral |
| 79 | — | — |
| 80 | oralCavity | protectedOral |
| 81 | oralCavity | protectedOral |
| 82 | oralCavity | protectedOral |
| 83 | — | — |
| 84 | lowerLip | protectedOral |
| 85 | — | — |
| 86 | — | — |
| 87 | oralCavity | protectedOral |
| 88 | oralCavity | protectedOral |
| 89 | — | — |
| 90 | — | — |
| 91 | lowerLip | protectedOral |
| 92 | — | — |
| 93 | skullContour | — |
| 94 | noseDorsum | — |
| 95 | — | — |
| 96 | — | — |
| 97 | noseDorsum | — |
| 98 | noseDorsum | — |
| 99 | — | — |
| 100 | — | — |
| 101 | — | — |
| 102 | — | — |
| 103 | skullContour, forehead, templeLeft | — |
| 104 | — | — |
| 105 | browRight | — |
| 106 | — | — |
| 107 | browRight | — |
| 108 | — | — |
| 109 | skullContour, forehead, templeLeft | — |
| 110 | — | — |
| 111 | — | — |
| 112 | — | — |
| 113 | — | — |
| 114 | — | — |
| 115 | noseAlae | — |
| 116 | cheekLeft | — |
| 117 | — | — |
| 118 | — | — |
| 119 | — | — |
| 120 | — | — |
| 121 | — | — |
| 122 | — | — |
| 123 | cheekLeft | — |
| 124 | — | — |
| 125 | — | — |
| 126 | cheekLeft | — |
| 127 | skullContour, templeLeft | — |
| 128 | — | — |
| 129 | — | — |
| 130 | — | — |
| 131 | — | — |
| 132 | skullContour, jawLeft | gonion |
| 133 | eyeRight | — |
| 134 | — | — |
| 135 | — | — |
| 136 | skullContour, jawLeft | chinJawHandle |
| 137 | — | — |
| 138 | — | — |
| 139 | — | — |
| 140 | — | — |
| 141 | — | — |
| 142 | cheekLeft | — |
| 143 | — | — |
| 144 | eyeRight | — |
| 145 | eyeRight | — |
| 146 | lowerLip | protectedOral |
| 147 | cheekLeft | — |
| 148 | skullContour, jawLeft, chin | chinContour |
| 149 | skullContour, jawLeft, chin | chinContour |
| 150 | skullContour, jawLeft, chin | chinContour |
| 151 | forehead | — |
| 152 | skullContour, jawLeft, jawRight, chin | chinTip |
| 153 | eyeRight | — |
| 154 | eyeRight | — |
| 155 | eyeRight | — |
| 156 | — | — |
| 157 | eyeRight | — |
| 158 | eyeRight | — |
| 159 | eyeRight | — |
| 160 | eyeRight | — |
| 161 | eyeRight | — |
| 162 | skullContour, templeLeft | — |
| 163 | eyeRight | — |
| 164 | philtrum | — |
| 165 | — | — |
| 166 | — | — |
| 167 | — | — |
| 168 | noseRoot | — |
| 169 | — | — |
| 170 | — | — |
| 171 | — | — |
| 172 | skullContour, jawLeft | chinJawHandle |
| 173 | eyeRight | — |
| 174 | — | — |
| 175 | chin | chinObserve |
| 176 | skullContour, jawLeft, chin | chinContour |
| 177 | — | — |
| 178 | oralCavity | protectedOral |
| 179 | — | — |
| 180 | — | — |
| 181 | lowerLip | protectedOral |
| 182 | — | — |
| 183 | — | — |
| 184 | — | — |
| 185 | upperLip | protectedOral |
| 186 | — | — |
| 187 | cheekLeft | — |
| 188 | — | — |
| 189 | — | — |
| 190 | — | — |
| 191 | oralCavity | protectedOral |
| 192 | — | — |
| 193 | — | — |
| 194 | — | — |
| 195 | noseRoot | — |
| 196 | — | — |
| 197 | noseRoot | — |
| 198 | — | — |
| 199 | chin | chinObserve |
| 200 | chin | chinObserve |
| 201 | — | — |
| 202 | — | — |
| 203 | cheekLeft | — |
| 204 | — | — |
| 205 | — | — |
| 206 | cheekLeft | — |
| 207 | cheekLeft | — |
| 208 | — | — |
| 209 | — | — |
| 210 | — | — |
| 211 | — | — |
| 212 | — | — |
| 213 | — | — |
| 214 | — | — |
| 215 | — | — |
| 216 | — | — |
| 217 | cheekLeft | — |
| 218 | — | — |
| 219 | — | — |
| 220 | noseAlae | — |
| 221 | — | — |
| 222 | — | — |
| 223 | — | — |
| 224 | — | — |
| 225 | — | — |
| 226 | — | — |
| 227 | — | — |
| 228 | — | — |
| 229 | — | — |
| 230 | — | — |
| 231 | — | — |
| 232 | — | — |
| 233 | — | — |
| 234 | skullContour | — |
| 235 | — | — |
| 236 | — | — |
| 237 | — | — |
| 238 | — | — |
| 239 | — | — |
| 240 | — | — |
| 241 | — | — |
| 242 | — | — |
| 243 | — | — |
| 244 | — | — |
| 245 | — | — |
| 246 | eyeRight | — |
| 247 | — | — |
| 248 | — | — |
| 249 | eyeLeft | — |
| 250 | — | — |
| 251 | skullContour, templeRight | — |
| 252 | — | — |
| 253 | — | — |
| 254 | — | — |
| 255 | — | — |
| 256 | — | — |
| 257 | — | — |
| 258 | — | — |
| 259 | — | — |
| 260 | — | — |
| 261 | — | — |
| 262 | — | — |
| 263 | eyeLeft | — |
| 264 | — | — |
| 265 | — | — |
| 266 | cheekRight | — |
| 267 | upperLip, philtrum | protectedOral |
| 268 | — | — |
| 269 | upperLip | protectedOral |
| 270 | upperLip | protectedOral |
| 271 | — | — |
| 272 | — | — |
| 273 | — | — |
| 274 | — | — |
| 275 | noseTip | — |
| 276 | browLeft | — |
| 277 | — | — |
| 278 | noseAlae | — |
| 279 | — | — |
| 280 | — | — |
| 281 | — | — |
| 282 | browLeft | — |
| 283 | browLeft | — |
| 284 | skullContour, templeRight | — |
| 285 | browLeft | — |
| 286 | — | — |
| 287 | — | — |
| 288 | skullContour, jawRight | gonion |
| 289 | — | — |
| 290 | — | — |
| 291 | mouthCorner | protectedOral |
| 292 | — | — |
| 293 | browLeft | — |
| 294 | noseAlae | — |
| 295 | browLeft | — |
| 296 | browLeft | — |
| 297 | skullContour, forehead, templeRight | — |
| 298 | — | — |
| 299 | — | — |
| 300 | browLeft | — |
| 301 | — | — |
| 302 | — | — |
| 303 | — | — |
| 304 | — | — |
| 305 | — | — |
| 306 | — | — |
| 307 | — | — |
| 308 | mouthCorner | protectedOral |
| 309 | — | — |
| 310 | oralCavity | protectedOral |
| 311 | oralCavity | protectedOral |
| 312 | oralCavity | protectedOral |
| 313 | — | protectedOral, labiomental |
| 314 | lowerLip | protectedOral |
| 315 | — | — |
| 316 | — | — |
| 317 | oralCavity | protectedOral |
| 318 | oralCavity | protectedOral |
| 319 | — | — |
| 320 | — | — |
| 321 | lowerLip | protectedOral |
| 322 | — | — |
| 323 | skullContour, jawRight | earLateral |
| 324 | oralCavity | protectedOral |
| 325 | — | — |
| 326 | noseAlae | — |
| 327 | noseAlae | — |
| 328 | — | — |
| 329 | — | — |
| 330 | — | — |
| 331 | — | — |
| 332 | skullContour, forehead, templeRight | — |
| 333 | — | — |
| 334 | browLeft | — |
| 335 | — | — |
| 336 | browLeft | — |
| 337 | forehead | — |
| 338 | skullContour, forehead, templeRight | — |
| 339 | — | — |
| 340 | — | — |
| 341 | — | — |
| 342 | — | — |
| 343 | — | — |
| 344 | noseAlae | — |
| 345 | cheekRight | — |
| 346 | — | — |
| 347 | — | — |
| 348 | — | — |
| 349 | — | — |
| 350 | — | — |
| 351 | — | — |
| 352 | cheekRight | — |
| 353 | — | — |
| 354 | — | — |
| 355 | — | — |
| 356 | skullContour, templeRight | — |
| 357 | — | — |
| 358 | — | — |
| 359 | — | — |
| 360 | — | — |
| 361 | skullContour, jawRight | gonion |
| 362 | eyeLeft | — |
| 363 | — | — |
| 364 | — | — |
| 365 | skullContour, jawRight | chinJawHandle |
| 366 | — | — |
| 367 | — | — |
| 368 | — | — |
| 369 | — | — |
| 370 | — | — |
| 371 | cheekRight | — |
| 372 | — | — |
| 373 | eyeLeft | — |
| 374 | eyeLeft | — |
| 375 | lowerLip | protectedOral |
| 376 | — | — |
| 377 | skullContour, jawLeft | chinContour |
| 378 | skullContour, jawRight | chinContour |
| 379 | skullContour, jawRight | chinContour |
| 380 | eyeLeft | — |
| 381 | eyeLeft | — |
| 382 | eyeLeft | — |
| 383 | — | — |
| 384 | eyeLeft | — |
| 385 | eyeLeft | — |
| 386 | eyeLeft | — |
| 387 | eyeLeft | — |
| 388 | eyeLeft | — |
| 389 | skullContour, templeRight | — |
| 390 | eyeLeft | — |
| 391 | — | — |
| 392 | — | — |
| 393 | philtrum | — |
| 394 | — | — |
| 395 | — | — |
| 396 | — | — |
| 397 | skullContour, jawRight | chinJawHandle |
| 398 | eyeLeft | — |
| 399 | — | — |
| 400 | skullContour, jawRight | chinContour |
| 401 | — | — |
| 402 | oralCavity | protectedOral |
| 403 | — | — |
| 404 | — | — |
| 405 | lowerLip | protectedOral |
| 406 | — | — |
| 407 | — | — |
| 408 | — | — |
| 409 | upperLip | protectedOral |
| 410 | — | — |
| 411 | cheekRight | — |
| 412 | — | — |
| 413 | — | — |
| 414 | — | — |
| 415 | oralCavity | protectedOral |
| 416 | — | — |
| 417 | — | — |
| 418 | — | — |
| 419 | — | — |
| 420 | — | — |
| 421 | — | protectedOral, labiomental |
| 422 | — | — |
| 423 | cheekRight | — |
| 424 | — | — |
| 425 | cheekRight | — |
| 426 | cheekRight | — |
| 427 | cheekRight | — |
| 428 | — | protectedOral, labiomental |
| 429 | — | — |
| 430 | — | — |
| 431 | — | — |
| 432 | — | — |
| 433 | — | — |
| 434 | — | — |
| 435 | — | — |
| 436 | cheekRight | — |
| 437 | — | — |
| 438 | — | — |
| 439 | — | — |
| 440 | noseTip | — |
| 441 | — | — |
| 442 | — | — |
| 443 | — | — |
| 444 | — | — |
| 445 | — | — |
| 446 | — | — |
| 447 | — | — |
| 448 | — | — |
| 449 | — | — |
| 450 | — | — |
| 451 | — | — |
| 452 | — | — |
| 453 | — | — |
| 454 | skullContour, jawRight | earLateral |
| 455 | — | — |
| 456 | — | — |
| 457 | — | — |
| 458 | — | — |
| 459 | — | — |
| 460 | — | — |
| 461 | — | — |
| 462 | — | — |
| 463 | — | — |
| 464 | — | — |
| 465 | — | — |
| 466 | eyeLeft | — |
| 467 | — | — |
| 468 | eyeLeft | iris |
| 469 | eyeLeft | iris |
| 470 | eyeLeft | iris |
| 471 | eyeLeft | iris |
| 472 | eyeLeft | iris |
| 473 | eyeRight | iris |
| 474 | eyeRight | iris |
| 475 | eyeRight | iris |
| 476 | eyeRight | iris |
| 477 | eyeRight | iris |
