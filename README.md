# MC3 Car Paint Tester (Godot 4.3+)

A Godot re-creation of the Midnight Club 3 car paint, rebuilt from the RenderDoc capture
(Xbox build, Vulkan) and the PS2 disassembly (`mcCarPaintJob`, `mcCarMetallicPaint`, `mcCityEnvMap`).

Open the folder in Godot 4.3 or newer (it should work from 4.2), let it import the glTF, press **F5**.
Drag = orbit, wheel = zoom. Everything is built from code in `main.gd`.

## Pipeline

| Game | Godot |
|---|---|
| `GenSpecular` -> `RenderHighlights` -> `DrawHilight`: 256x256 "paint" render target | `shaders/paint_map.gdshader` in a 256x256 `SubViewport` |
| `mcCityEnvMap::DrawSky` + light glows: 256x256 envmap | `shaders/env_map.gdshader` in a 256x256 `SubViewport` |
| NV2A vertex program + register combiners (EID 4054) | `shaders/car_paint.gdshader` (unshaded spatial) |
| `SetupMetallic/Pearl/GlossGradient`, `MakeGradient`, `SetupImage` | `_gradient_colors()` in `main.gd` + the sprite maths in `paint_map.gdshader` |

### Paint map
1. Fill with the base colour (gradient stop 1).
2. For each light (up to 10), find the half vector `H = normalize(toLight + toCamera)` seen from the car,
   express it in view space, and draw a glow sprite at the map position of that normal.
   Sprite alpha = intensity * (1 - distance / 25 m); sprite half-size = size * 0.3 (ortho units).
3. The sprite is a radial gradient: `colour = mix(A, B, t)`, `alpha = 1 - t`, blended SrcAlpha + One.

Gradient stops: Metallic `A = clamp(normalize(B) * 1.5)` (the capture matches 1.5 exactly),
Pearl `A = second colour`, Gloss `A = 0.85 * B`.

### Env map
* A 360 degree panorama is added over the whole target; its u offset is the camera heading (`atan2 / 2pi`).
* Light glows are projected through a perspective camera (garage FOV 100, city 140) that sits at the car
  and looks AWAY from the player camera (`LookDown(eye - target)`), then added as soft round sprites.
* Alpha = reflection strength, flat 0.361 in the capture.
* The real panorama is a game asset, so a procedural garage-like one is generated; "Load panorama..." takes any image.

### Car shader
```
COLOR0.rgb = (ambient + sum max(N.-L_i, 0) * colour_i) * material
COLOR0.a   = clamp((1 - n.z) * scale + bias, min, max)           (Fresnel-like)
uv         = (a * clipPos.xy + s * clipNormal.xy) * scale + bias  (paint map and env map, different a)
lit        = clamp(paint(uv0) * COLOR0.rgb * 2)
ea         = clamp(env.a * COLOR0.a * 2)
out        = env.rgb * ea + lit * (1 - ea)
```
Both lookups are screen aligned, normal-indexed (matcap style). The game does this per vertex; the
"per-pixel lookup" checkbox gives the smoother version.

## Values taken from the capture
* Paint map: stop 1 (base) = (53, 25, 7), stop 0 = (255, 161, 47), highlight alpha about 0.6, sprite FWHM about 46 px.
* Env alpha: constant 92/255.
* Body colour scale 0.25: maps a bright picker colour to the dark stop-1 values the game stores.

## Not recovered / guessed
* Constants `c112`, `c116`, `c117`, `c146` (map scale/bias, position weights, Fresnel terms), vertex light
  directions/colours, and the per-paint-type size/intensity table: tuned by eye, all exposed as sliders.
* The v orientation of the paint map and the exact `DrawHilight` placement. The disassembly gives a non-linear
  formula that does not match the linear vertex lookup, so the default places each highlight exactly where the
  lookup reads (normal = half vector). The game's formula is available as an experimental checkbox.
* The original panorama and the garage geometry that the game draws into the envmap.

## Credits
Model: "Paint tester" by tifaiter, https://sketchfab.com/3d-models/paint-tester-72688c1de13348199dda4899b261b5b7,
licensed CC-BY-4.0 (see `model/license.txt`).
