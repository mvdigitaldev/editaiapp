# Filtros Faciais — Roadmap

Todos implementados como `BeautyFilter` em `beauty_engine/filters/face/`, consumindo Mesh + Warp + GPU.

## Lista completa

| ID | Nome | Tipo | Sprint |
|----|------|------|--------|
| `face_slim` | Face Slim | Warp | 10 |
| `narrow_face` | Narrow Face | Warp | 10 |
| `v_face` | V Face | Warp | 10 |
| `cheekbone` | Cheekbone | Warp | 14 |
| `jaw` | Jaw | Warp | 13 |
| `chin` | Chin | Warp | 13 |
| `forehead` | Forehead | Warp | 15 |
| `temple` | Temple | Warp | 15 |
| `eye_scale` | Eye Scale | Warp | 12 |
| `eye_distance` | Eye Distance | Warp | 12 |
| `eye_height` | Eye Height | Warp | 12 |
| `eye_rotation` | Eye Rotation | Warp | 12 |
| `double_eyelid` | Double Eyelid | Warp + shader | 12 |
| `nose_slim` | Nose Slim | Warp | 11 |
| `nose_length` | Nose Length | Warp | 11 |
| `nose_height` | Nose Height | Warp | 11 |
| `nose_tip` | Nose Tip | Warp | 11 |
| `nose_bridge` | Nose Bridge | Warp | 11 |
| `mouth_width` | Mouth Width | Warp | 16 |
| `lip_thickness` | Lip Thickness | Warp | 16 |
| `smile` | Smile | Warp | 16 |
| `teeth_whitening` | Teeth Whitening | Shader | 17 |
| `skin_smooth` | Skin Smooth | Shader | 17 |
| `skin_whitening` | Skin Whitening | Shader | 17 |
| `remove_acne` | Remove Acne | Shader + ML optional | 17 |
| `remove_wrinkles` | Remove Wrinkles | Shader | 17 |
| `remove_dark_circles` | Remove Dark Circles | Shader | 17 |
| `makeup` | Makeup (composite) | Shader layers | 17 |
| `eyebrows` | Eyebrows | Shader overlay | 17 |
| `eyelashes` | Eyelashes | Shader overlay | 17 |
| `blush` | Blush | Shader overlay | 17 |
| `contour` | Contour | Shader overlay | 17 |

## Implementação padrão por filtro warp

1. Definir `MeshRegion` afetada
2. Calcular control points offset = f(intensity, landmarks)
3. Delegar a `WarpEngine.compute`
4. Compor no pipeline GPU

## Implementação padrão por filtro shader

1. Máscara região (face oval minus eyes/mouth)
2. Pass bilateral / curve adjustment
3. Blend com feather

## Dependências

- Sprint 05 Mesh Engine
- Sprint 06 Warp Engine
- Sprint 07 GPU Rendering
