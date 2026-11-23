shader_type spatial;
render_mode unshaded, cull_back;

// MC3 car paint, verified against the Xbox capture (draw EID 4054: correlation 1.000,
// mean error 0.001 over 13846 pixels).
//
// Vertex stage (NV2A vertex program):
//   COLOR0.rgb = clamp((ambient + sum_i max(N.-L_i, floor) * lightColor_i) * material)
//   COLOR0.a   = clamp((1 - n.z) * c146.w, c146.y, c146.z)         (Fresnel-like, n.z towards the viewer)
//   uv         = (a * clip.xy + s * nclip.xy) * scale + 0.5
//                 clip  = MVP * position (undivided), nclip = MVP rotation part * normal
//                 s = c116.w = 0.25, scale = k * (0.35 + 0.65 * (fov - 25) / 40), fov = vertical FOV in degrees
//                 paint map: a = c117.z = 0.05, env map: a = c146.x * c116.w
//   v grows with the normal's UP component (texture rows run top to bottom).
//
// Pixel stage (hand written combiners):
//   lit = clamp(paintMap(uv0) * COLOR0.rgb * 2)
//   ea  = clamp(envMap.a * COLOR0.a * 2)
//   out = envMap.rgb * ea + lit * (1 - ea)

uniform sampler2D paint_map : filter_linear, repeat_disable;
uniform sampler2D env_map : filter_linear, repeat_disable;

// vertex lighting: 3 directional lights (world space, direction the light TRAVELS) + ambient
uniform vec3 light_dir0 = vec3(0.63797, -0.50528, -0.58111);
uniform vec3 light_dir1 = vec3(0.0, -0.95783, -0.28735);
uniform vec3 light_dir2 = vec3(-0.57735, -0.57735, -0.57735);
uniform vec3 light_col0 = vec3(0.34036);
uniform vec3 light_col1 = vec3(0.25);
uniform vec3 light_col2 = vec3(0.0);
uniform vec3 ambient = vec3(0.065);
uniform float diffuse_floor = 0.0;
uniform float material_mul = 1.0;

// texture coordinate generation
uniform float lookup_scale = 0.64248;
uniform float normal_weight = 0.25;
uniform float paint_pos_weight = 0.05;
uniform float env_pos_weight = 0.11;
uniform bool keep_model_scale = false;   // the game does not renormalise the transformed normal
uniform bool per_pixel_lookup = false;   // false = per vertex like the game

// reflection weight
uniform float fres_min = 0.275;
uniform float fres_max = 1.0;
uniform float fres_scale = 0.675;
uniform float reflect_gain = 1.0;
uniform float paint_gain = 1.0;
uniform bool gamma_correct = true;

varying vec2 v_paint_uv;
varying vec2 v_env_uv;
varying vec4 v_color0;
varying vec3 v_nview;
varying vec3 v_pview;

vec2 mc3_uv(vec3 n, vec3 p, float pos_weight, mat4 proj) {
	float fx = proj[0][0];
	float fy = abs(proj[1][1]);
	vec2 clip_xy = vec2(fx * p.x, fy * p.y);
	vec2 n_clip = vec2(fx * n.x, fy * n.y);
	return (pos_weight * clip_xy + normal_weight * n_clip) * lookup_scale + vec2(0.5);
}

float fresnel_weight(vec3 n) {
	return clamp((1.0 - n.z) * fres_scale, fres_min, fres_max);
}

vec3 srgb_to_linear(vec3 c) {
	vec3 lo = c / 12.92;
	vec3 hi = pow((c + 0.055) / 1.055, vec3(2.4));
	return mix(hi, lo, step(c, vec3(0.04045)));
}

void vertex() {
	vec3 n = mat3(MODELVIEW_MATRIX) * NORMAL;
	vec3 nw = mat3(MODEL_MATRIX) * NORMAL;
	if (!keep_model_scale) {
		n = normalize(n);
		nw = normalize(nw);
	}
	vec3 p = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	float d0 = max(dot(nw, -normalize(light_dir0)), diffuse_floor);
	float d1 = max(dot(nw, -normalize(light_dir1)), diffuse_floor);
	float d2 = max(dot(nw, -normalize(light_dir2)), diffuse_floor);
	vec3 light = ambient + d0 * light_col0 + d1 * light_col1 + d2 * light_col2;

	v_color0 = vec4(clamp(light * material_mul, 0.0, 1.0), fresnel_weight(n));
	v_paint_uv = mc3_uv(n, p, paint_pos_weight, PROJECTION_MATRIX);
	v_env_uv = mc3_uv(n, p, env_pos_weight, PROJECTION_MATRIX);
	v_nview = n;
	v_pview = p;
}

void fragment() {
	vec2 puv = v_paint_uv;
	vec2 euv = v_env_uv;
	float fw = v_color0.a;
	if (per_pixel_lookup) {
		vec3 n = v_nview;
		if (!keep_model_scale) {
			n = normalize(n);
		}
		puv = mc3_uv(n, v_pview, paint_pos_weight, PROJECTION_MATRIX);
		euv = mc3_uv(n, v_pview, env_pos_weight, PROJECTION_MATRIX);
		fw = fresnel_weight(n);
	}

	vec3 base = texture(paint_map, puv).rgb;
	vec4 env = texture(env_map, euv);

	vec3 lit = clamp(base * v_color0.rgb * 2.0 * paint_gain, 0.0, 1.0);
	float ea = clamp(env.a * fw * 2.0 * reflect_gain, 0.0, 1.0);
	vec3 col = env.rgb * ea + lit * (1.0 - ea);

	ALBEDO = gamma_correct ? srgb_to_linear(col) : col;
}
