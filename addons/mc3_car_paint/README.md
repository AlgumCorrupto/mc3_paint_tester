# MC3 Car Paint (Godot 4.3+ addon)

Midnight Club 3 style **car paint**, **chrome** and **glass** as a drop-in node, rebuilt from a RenderDoc capture (Xbox build,
Vulkan) and the game's disassembly (`mcCarPaintJob`, `mcCarMetallicPaint`, `mcCityEnvMap`, `drwShader*Chrome`).
The shading maths was checked against the capture pixel by pixel (see "Verified").

## Install
Copy `addons/mc3_car_paint/` into your project's `addons/` folder (keep the folder name, the icon path depends on it)
and optionally enable it in Project Settings > Plugins. The classes register themselves through `class_name`;
the plugin only adds *Project > Tools > MC3 Car Paint: add paint node to selected node(s)*.

## Use
1. Add an **MC3CarPaint** node as a child of your car (or set its `target`). Every `MeshInstance3D` below the
   target gets the car paint material, except:

   | Group on the mesh (or any parent) | Result |
   |---|---|
   | `mc3_chrome` | chrome, tinted by `chrome_color` |
   | `mc3_rim_chrome` | chrome, tinted by `rim_chrome_color` |
   | `mc3_exhaust_chrome` | chrome, tinted by `exhaust_chrome_color` |
   | `mc3_glass` | alpha blended glass, `glass_tint` / `glass_opacity` |
   | `mc3_headlight_glass` | glass lit by `headlights_on` |
   | `mc3_brakelight_glass` | glass lit by `headlights_on` + `brakelights_on` |
   | `mc3_paint_ignore` | untouched |

2. Make sure the scene has a `Camera3D` (the active one is used) and, ideally, some `OmniLight3D` / `SpotLight3D`
   nodes: their positions drive the highlights and the glows in the reflection. With no lights the built-in garage rig is used.
3. Tweak the properties in the inspector (grouped: Paint, Highlights, Environment, Vertex lighting,
   Lookup and reflection, Chrome) or from code:

```gdscript
var paint := MC3CarPaint.new()
car.add_child(paint)
paint.base_color = Color(0.1, 0.25, 0.9)
paint.paint_type = MC3CarPaint.PaintType.PEARL
paint.pearl_color = Color(0.6, 0.9, 1.0)
paint.rim_chrome_color = Color(1.0, 0.85, 0.5)
$Wheel.add_to_group("mc3_rim_chrome")
paint.refresh_targets()          # after changing groups / adding meshes
```

The effect runs at run time only (it needs the active camera every frame).

### Panoramas (env map and background)
The env map shows an equirectangular (2:1) panorama. Without one a procedural garage-like panorama is used.
```gdscript
paint.panorama = load("res://my_panorama.jpg")     # any equirectangular image, any size
paint.panorama_match_sky = true                    # reflect what is behind the camera (see below)
environment.background_mode = Environment.BG_SKY
environment.sky = paint.get_sky()                  # same image as the scene background, follows paint.panorama
```
* `MC3CarPaintPanel.panorama_presets` is a `Dictionary` of name -> `Texture2D`; the panel shows it as a drop-down
  (next to "Procedural (built-in)") and a "Load panorama..." button for any image file.
* The panorama is copied to a mipmapped texture (at most 2048 wide) because the env map is only 256x256.
* **`panorama_match_sky` off** (default) is the game's behaviour: the panorama is blitted flat across the env map,
  scrolled by the camera yaw only. **On**, the reflection is physically oriented: it shows what is behind the camera,
  follows yaw and pitch, and uses the same equirect convention as `get_sky()`
  (`u = atan(x, -z) / 2pi + 0.5`, `v = acos(y) / pi`), so background and reflections agree.
* The env map keeps the game's blend: `sky_color + panorama * 0.5 * panorama_gain` (default gain 2.0, matched to the
  capture's envmap brightness). Lower the gain for very bright panoramas.

### Ready-made UI
```gdscript
var panel := MC3CarPaintPanel.new()
panel.bind(paint)
$CanvasLayer.add_child(panel)
panel.content.add_child(my_extra_control)   # extend it
```

## API
| Member | Description |
|---|---|
| `target`, `camera`, `auto_center` | what to paint, which camera to use, where the "car" is |
| `base_color`, `paint_type`, `pearl_color`, `body_color_scale`, `metallic_scale`, `gradient_start` | paint |
| `highlight_size/intensity`, `light_fade_distance`, `max_lights`, `camera_light`, `light_sources`, `auto_collect_lights`, `use_fallback_rig` | highlights in the paint map |
| `reflection_alpha`, `panorama`, `panorama_gain`, `panorama_match_sky`, `panorama_flip_v`, `light_dot_gain`, `env_fov` | environment map |
| `ambient`, `vertex_light_scale`, `lightN_direction/color` | vertex lighting (COLOR0), defaults are the capture's values |
| `auto_lookup_scale`, `lookup_scale_k`, `normal_weight`, `paint_position_weight`, `fresnel_*` | lookup and Fresnel-like weight (the game's c112, c116.w, c117.z, c146) |
| `chrome_color`, `rim_chrome_color`, `exhaust_chrome_color`, `chrome_ambient_lift`, `chrome_position_weight` | chrome |
| `glass_tint`, `glass_opacity`, `headlight_glass_*`, `brakelight_glass_*`, `headlights_on`, `brakelights_on`, `glass_position_weight`, `glass_fresnel_*` | glass |
| `get_material()`, `get_chrome_material(kind)`, `get_glass_material(kind)` | the `ShaderMaterial`s (assign them to more meshes) |
| `apply_to(node)` | paint another subtree (groups are honoured) |
| `refresh_targets()` / `refresh_lights()` | re-scan after changing the scene |
| `get_paint_texture()` / `get_env_texture()` / `get_lookup_scale()` | generated 256x256 maps, current lookup scale |
| `get_center()` / `get_bounds()` | car position and bounds used by the effect |
| `set_panorama_from_file(path)` | load a custom lat/long panorama |
| `get_sky()` | a `Sky` showing the current panorama with the reflection's orientation |

## How it works

| Game | Addon |
|---|---|
| `GenSpecular` -> `RenderHighlights` -> `DrawHilight` (256x256 paint target) | `shaders/paint_map.gdshader` in a `SubViewport` |
| `mcCityEnvMap::DrawSky` + light glows (256x256 env map) | `shaders/env_map.gdshader` in a `SubViewport` |
| car paint vertex program + hand written combiners | `shaders/car_paint.gdshader` |
| `drwShaderChrome` family, fixed function combiner | `shaders/chrome.gdshader` |
| `drwShaderColoredGlass` (+ headlight / brakelight), hand written combiner, alpha blend | `shaders/glass.gdshader` |
| `SetupMetallic/Pearl/GlossGradient`, `MakeGradient`, `SetupImage` | `MC3CarPaint._gradient_colors()` + the sprite maths in the paint map shader |

### Lookup (paint map, env map and chrome)
```
clip   = MVP * position            (undivided, y up)
nclip  = MVP rotation part * normal
uv     = (a * clip.xy + s * nclip.xy) * scale + 0.5
scale  = k * (0.35 + 0.65 * (fov - 25) / 40)     fov = vertical FOV in degrees (FixupTexMatrices), k = 1
s      = 0.25                                    (c116.w)
a      = 0.05 paint map (c117.z), 0.44 * 0.25 env map (c146.x * c116.w), 0.8 * 0.25 chrome
```
`v` grows with the normal's **up** component, i.e. up-facing surfaces read the lower half of the maps
(`panorama_flip_v` flips the panorama if you want an upright one to show its ceiling on roofs).

### Car paint combiner
```
COLOR0.rgb = (ambient + sum max(N.-L_i, 0) * lightColor_i) * material
COLOR0.a   = clamp((1 - n.z) * 0.675, 0.275, 1.0)
lit        = clamp(paintMap(uv0) * COLOR0.rgb * 2)
ea         = clamp(envMap.a * COLOR0.a * 2)
out        = envMap.rgb * ea + lit * (1 - ea)
```

### Chrome combiner
```
ambient'   = ambient + (1 - ambient) * 0.2                 (chrome_color_a)
COLOR0.rgb = clamp((ambient' + sum max(N.-L_i, 0) * lightColor_i) * chrome_color)
out        = clamp(COLOR0.rgb * envMap(uv).rgb * 2)
```

### Glass combiner
```
ambient'   = ambient + (1 - ambient) * light_lift            light_lift = 0 | 0.5*headlight | 0.5*headlight + 0.5*brakelight
COLOR0.rgb = clamp((ambient' + sum max(N.-L_i, 0) * lightColor_i) * material)
COLOR0.a   = clamp((1 - n.z) * 1.5, 0.124, 1.0)              glassFresnelParams = (0.9, 0.124, 1.0, 1.5)
lit        = clamp(tint * COLOR0.rgb * 2)
ea         = clamp(envMap.a * COLOR0.a * 2)
out.rgb    = envMap.rgb * ea + lit * (1 - ea)                 env lookup with a = 0.9 * 0.25
out.alpha  = opacity                                         blend SrcAlpha / InvSrcAlpha, RGB write only
```
Capture values: tint (22, 22, 22)/255, opacity 115/255 (the `.shadert` arguments of the coloured glass).
Face-on the reflection weight is at its minimum (about 0.09 after the x2), at grazing angles it reaches 0.7+,
so the glass is dark and see-through in the middle and mirror-like at the edges.

### Paint map and env map
Per light the paint map gets a glow sprite where the normal equal to the half vector between "to light" and
"to camera" is looked up (same mapping as the car shader). The sprite is a radial gradient
(`colour = mix(A, B, t)`, `alpha = 1 - t`), blended additively; stop 1 is the base colour, stop 0 is
`clamp(normalize(B) * 1.5)` for Metallic. The env map is a camera-heading-scrolled panorama plus perspective
projected light glows, seen from the car looking back at the viewer.

## Verified against the capture
| Draw | What | Result |
|---|---|---|
| EID 4054 (car body) | full car paint, rebuilt from the dumped vertices, constants and textures | correlation 1.000, mean error 0.001 (0-1 scale), p95 0.002, 13846 pixels |
| EID 3912 (wheel spokes) | chrome | mean error 0.005, p95 0.002 |
| EID 4410 (coloured glass) | glass: pixel shader and constants read exactly, vertex program identical to the car paint's; the alpha blend was only checked indirectly (regression of the final colour on the predicted glass colour: slope 0.42 vs opacity 0.451) | needs the frame before the draw for a pixel exact check |

Constants from the capture used as defaults: ambient 0.065, light 0 = 0.34036 along (0.638, -0.505, -0.581),
light 1 = 0.25 along (0, -0.958, -0.287), `c112` scale 0.64248 (= FOV 43 degrees), `c116.w` 0.25, `c117.z` 0.05,
`c146` = (0.44, 0.275, 1.0, 0.675) for the car paint and (0.8, 1, 1, 1) for chrome, env alpha 0.361,
metallic highlight scale 1.5, highlight alpha about 0.6, sprite FWHM about 46 px.

## Not recovered / guessed
* The game's own panorama (a game asset): a procedural garage-like one is generated by default, or use any equirect image. Brightness is matched to the capture's envmap.
* The exact `DrawHilight` placement: the disassembly gives a non-linear formula that was never checked against
  pixels. The default places each highlight where the verified lookup reads (normal = half vector);
  the game's formula is available as `game_placement_formula`.
* The orientation of env map light dots: derived from the verified lookup and the game's 180 degree camera roll,
  not from a pixel comparison.
* Glass tint and opacity of the headlight and brakelight variants (the capture only has plain smoked glass), and the
  game's gamma-space blending (Godot blends in linear space after the sRGB conversion).
* Per-paint-type highlight size/intensity, the real light positions, fog, and how model scale enters the lookup
  (the game does not renormalise the transformed normal; `keep_model_scale` reproduces that).
