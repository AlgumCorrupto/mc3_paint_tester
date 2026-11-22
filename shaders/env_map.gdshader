shader_type canvas_item;
render_mode blend_disabled;

// Environment map of the MC3 car paint (256x256 render target).
//
// Recreates the mcCityEnvMap path used by the garage:
//   * DrawSky: a 360-degree panorama (fx_static_envmap_*) is blitted over the WHOLE
//     target; its u start is the camera heading (atan2 / 2pi), v spans the full height.
//     It is added on top of the sky/garage base (blend One + One).
//   * RenderLights / RenderLightGlows: soft round sprites at the projected light
//     positions, blended SrcAlpha + One.
//   * The alpha channel is the reflection strength; the car shader multiplies it with
//     a per-vertex Fresnel-like term. In the capture it is a flat ~0.36.
//
// The original panorama is a game asset, so a procedural garage-like one is generated
// here. A custom image can be supplied through pano_tex.

const int MAX_DOTS = 12;

uniform float heading = 0.0;                       // panorama u offset (turns)
uniform float pano_gain = 1.0;
uniform vec3 sky_color = vec3(0.10, 0.105, 0.11);  // what is under the panorama
uniform bool use_custom_pano = false;
uniform sampler2D pano_tex : filter_linear, repeat_enable;
uniform float reflect_alpha = 0.361;

// 12x1 RGBAF texture: xy = dot centre (UV), z = dot half-size (UV), w = alpha
uniform sampler2D dot_data : filter_nearest, repeat_disable;
uniform int dot_count = 0;
uniform float dot_gain = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// value noise that repeats every `px` cells in x (so the panorama wraps seamlessly)
float pnoise(vec2 p, float px) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, px);
	float x1 = mod(i.x + 1.0, px);
	float a = hash12(vec2(x0, i.y));
	float b = hash12(vec2(x1, i.y));
	float c = hash12(vec2(x0, i.y + 1.0));
	float d = hash12(vec2(x1, i.y + 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Garage-like 360 degree panorama. x = azimuth (turns), y = 0 zenith .. 1 nadir.
vec3 procedural_pano(vec2 uv) {
	float x = fract(uv.x);
	float y = clamp(uv.y, 0.0, 1.0);

	float ceiling = 1.0 - smoothstep(0.36, 0.50, y);
	float floor_m = smoothstep(0.58, 0.78, y);
	vec3 col = mix(vec3(0.34, 0.35, 0.36), vec3(0.22, 0.22, 0.23), floor_m);
	col = mix(col, vec3(0.12, 0.125, 0.13), ceiling);

	// ceiling strip lights (6 around) and their faint floor reflection
	float seg = fract(x * 6.0);
	float strip_u = smoothstep(0.06, 0.12, seg) * (1.0 - smoothstep(0.60, 0.66, seg));
	float strip_v = 1.0 - smoothstep(0.0, 0.022, abs(y - 0.25));
	col += vec3(1.6, 1.55, 1.4) * strip_u * strip_v;
	float refl_v = 1.0 - smoothstep(0.0, 0.03, abs(y - 0.77));
	col += vec3(0.45, 0.44, 0.40) * strip_u * refl_v;

	// wall pillars and bright door openings
	float pillar = smoothstep(0.42, 0.48, abs(fract(x * 8.0 + 0.3) - 0.5));
	float wall_band = smoothstep(0.42, 0.47, y) * (1.0 - smoothstep(0.62, 0.68, y));
	col *= 1.0 - 0.55 * pillar * wall_band;
	float door_seg = fract(x * 3.0 + 0.15);
	float door = smoothstep(0.30, 0.32, door_seg) * (1.0 - smoothstep(0.52, 0.54, door_seg));
	col += vec3(0.55, 0.60, 0.70) * door * wall_band;

	// horizontal streaking (the original panorama is smeared sideways)
	float n = pnoise(vec2(x * 24.0, y * 70.0), 24.0);
	col *= 0.6 + 0.8 * n;
	return col;
}

void fragment() {
	vec2 pu = vec2(UV.x + heading, UV.y);
	vec3 pano = use_custom_pano ? texture(pano_tex, pu).rgb : procedural_pano(pu);
	vec3 col = sky_color + pano * 0.5 * pano_gain;   // 3619 adds the panorama at vertex alpha 0.5
	float alpha = reflect_alpha;

	for (int i = 0; i < MAX_DOTS; i++) {
		if (i >= dot_count) {
			break;
		}
		vec4 D = texelFetch(dot_data, ivec2(i, 0), 0);
		float r = clamp(length((UV - D.xy) / max(D.z, 0.0001)), 0.0, 1.0);
		float blob = 1.0 - smoothstep(0.0, 1.0, r);   // soft round sprite alpha
		float a = blob * D.w * dot_gain;
		col += vec3(1.0) * a;                        // SrcAlpha, One
		alpha += a * 0.2;
	}
	COLOR = vec4(clamp(col, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
}
