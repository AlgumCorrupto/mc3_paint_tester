shader_type spatial;
render_mode unshaded, cull_back;

// MC3 car paint, as found in the Xbox capture (draw EID 4054).
//
// Vertex stage (NV2A vertex program):
//   COLOR0.rgb = (ambient + sum_i max(N.-L_i, floor) * lightColor_i) * material
//   COLOR0.a   = clamp((nz + bias) * scale, min, max)        // Fresnel-like reflection weight
//   TEXCOORD0  = (a * clipPos.xy + s * clipNormal.xy) * scale + bias   -> paint map
//   TEXCOORD2  = same form with a different position weight             -> env map
//   (clipNormal = normal rotated by the MVP matrix, i.e. a screen aligned, matcap style lookup)
//
// Pixel stage (register combiners):
//   base  = paintMap(TEXCOORD0)
//   lit   = clamp(base * COLOR0.rgb * 2)
//   ea    = clamp(envMap.a * COLOR0.a * 2)
//   out   = envMap.rgb * ea + lit * (1 - ea)

uniform sampler2D paint_map : filter_linear, repeat_disable;
uniform sampler2D env_map : filter_linear, repeat_disable;

// vertex lighting: 3 directional lights (world space, direction the light TRAVELS) + ambient
uniform vec3 light_dir0 = vec3(-0.35, -0.75, -0.55);
uniform vec3 light_dir1 = vec3(0.80, -0.30, 0.45);
uniform vec3 light_dir2 = vec3(0.10, -0.20, 0.97);
uniform vec3 light_col0 = vec3(0.34);
uniform vec3 light_col1 = vec3(0.14);
uniform vec3 light_col2 = vec3(0.09);
uniform vec3 ambient = vec3(0.30);
uniform float diffuse_floor = 0.0;
uniform float material_mul = 1.4;

// texture coordinate generation
uniform float paint_normal_scale = 1.0;
uniform float paint_pos_weight = 0.0;
uniform float env_normal_scale = 1.0;
uniform float env_pos_weight = 0.03;
uniform bool per_pixel_lookup = false;   // false = per-vertex like the game

// reflection weight
uniform float fres_bias = 0.15;
uniform float fres_scale = 1.0;
uniform float fres_min = 0.10;
uniform float fres_max = 1.00;
uniform float reflect_gain = 1.0;
uniform float paint_gain = 1.0;
uniform bool gamma_correct = true;

varying vec2 v_paint_uv;
varying vec2 v_env_uv;
varying vec4 v_color0;
varying vec3 v_nview;
varying vec3 v_pview;

vec2 matcap_uv(vec3 n, vec3 p, float nscale, float pweight) {
	vec2 m = n.xy * nscale + p.xy * pweight;
	return vec2(0.5 + 0.5 * m.x, 0.5 - 0.5 * m.y);
}

float fresnel_weight(vec3 n) {
	return clamp((1.0 - n.z) * fres_scale + fres_bias, fres_min, fres_max);
}

vec3 srgb_to_linear(vec3 c) {
	vec3 lo = c / 12.92;
	vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
	return mix(hi, lo, step(c, vec3(0.04045)));
}

void vertex() {
	vec3 n = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec3 p = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec3 nw = normalize(mat3(MODEL_MATRIX) * NORMAL);
	float d0 = max(dot(nw, -normalize(light_dir0)), diffuse_floor);
	float d1 = max(dot(nw, -normalize(light_dir1)), diffuse_floor);
	float d2 = max(dot(nw, -normalize(light_dir2)), diffuse_floor);
	vec3 light = ambient + d0 * light_col0 + d1 * light_col1 + d2 * light_col2;

	v_color0 = vec4(light * material_mul, fresnel_weight(n));
	v_paint_uv = matcap_uv(n, p, paint_normal_scale, paint_pos_weight);
	v_env_uv = matcap_uv(n, p, env_normal_scale, env_pos_weight);
	v_nview = n;
	v_pview = p;
}

void fragment() {
	vec2 puv = v_paint_uv;
	vec2 euv = v_env_uv;
	float fw = v_color0.a;
	if (per_pixel_lookup) {
		vec3 n = normalize(v_nview);
		puv = matcap_uv(n, v_pview, paint_normal_scale, paint_pos_weight);
		euv = matcap_uv(n, v_pview, env_normal_scale, env_pos_weight);
		fw = fresnel_weight(n);
	}

	vec3 base = texture(paint_map, puv).rgb;
	vec4 env = texture(env_map, euv);

	vec3 lit = clamp(base * v_color0.rgb * 2.0 * paint_gain, 0.0, 1.0);
	float ea = clamp(env.a * fw * 2.0 * reflect_gain, 0.0, 1.0);
	vec3 col = env.rgb * ea + lit * (1.0 - ea);

	ALBEDO = gamma_correct ? srgb_to_linear(col) : col;
}
