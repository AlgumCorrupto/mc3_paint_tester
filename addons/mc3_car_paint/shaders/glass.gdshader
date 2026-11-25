shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque;

// MC3 coloured glass (drwShaderColoredGlass, with its headlight / brakelight variants).
// Rebuilt from draw EID 4410 of the Xbox capture (hand written combiner, SrcAlpha / InvSrcAlpha blend)
// and from the PS2 code (Load / Bind / glassFresnelParams).
//
// It is the car paint pipeline with the paint map replaced by a flat tint, and an alpha blended output:
//
//   ambient'   = ambient + (1 - ambient) * light_lift       light_lift = 0.5 * headlight [+ 0.5 * brakelight]
//   COLOR0.rgb = clamp((ambient' + sum_i max(N.-L_i, 0) * lightColor_i) * material)
//   COLOR0.a   = clamp((1 - n.z) * 1.5, 0.124, 1.0)                  glassFresnelParams = (0.9, 0.124, 1.0, 1.5)
//   uv         = (a * clip.xy + s * nclip.xy) * scale + 0.5           a = 0.9 * 0.25, same lookup as the car paint
//   lit        = clamp(tint * COLOR0.rgb * 2)
//   ea         = clamp(envMap.a * COLOR0.a * 2)
//   out.rgb    = envMap.rgb * ea + lit * (1 - ea)
//   out.alpha  = opacity                                              (capture: tint 22/255 grey, opacity 115/255)
//
// Built-in variables (PROJECTION_MATRIX ...) are not visible inside custom functions, so they are passed in.

uniform sampler2D env_map : filter_linear, repeat_disable;

uniform vec3 glass_tint = vec3(0.0863);
uniform float glass_opacity = 0.451;
uniform float light_lift = 0.0;

uniform vec3 light_dir0 = vec3(0.63797, -0.50528, -0.58111);
uniform vec3 light_dir1 = vec3(0.0, -0.95783, -0.28735);
uniform vec3 light_dir2 = vec3(-0.57735, -0.57735, -0.57735);
uniform vec3 light_col0 = vec3(0.34036);
uniform vec3 light_col1 = vec3(0.25);
uniform vec3 light_col2 = vec3(0.0);
uniform vec3 ambient = vec3(0.065);

uniform float lookup_scale = 0.64248;
uniform float normal_weight = 0.25;
uniform float env_pos_weight = 0.225;
uniform bool keep_model_scale = false;
uniform bool per_pixel_lookup = false;

uniform float fres_min = 0.124;
uniform float fres_max = 1.0;
uniform float fres_scale = 1.5;
uniform float reflect_gain = 1.0;
uniform bool gamma_correct = true;

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

	vec3 amb = ambient + (vec3(1.0) - ambient) * light_lift;
	float d0 = max(dot(nw, -normalize(light_dir0)), 0.0);
	float d1 = max(dot(nw, -normalize(light_dir1)), 0.0);
	float d2 = max(dot(nw, -normalize(light_dir2)), 0.0);
	vec3 light = amb + d0 * light_col0 + d1 * light_col1 + d2 * light_col2;

	v_color0 = vec4(clamp(light, 0.0, 1.0), fresnel_weight(n));
	v_env_uv = mc3_uv(n, p, env_pos_weight, PROJECTION_MATRIX);
	v_nview = n;
	v_pview = p;
}

void fragment() {
	vec2 euv = v_env_uv;
	float fw = v_color0.a;
	if (per_pixel_lookup) {
		vec3 n = v_nview;
		if (!keep_model_scale) {
			n = normalize(n);
		}
		euv = mc3_uv(n, v_pview, env_pos_weight, PROJECTION_MATRIX);
		fw = fresnel_weight(n);
	}

	vec4 env = texture(env_map, euv);
	vec3 lit = clamp(glass_tint * v_color0.rgb * 2.0, 0.0, 1.0);
	float ea = clamp(env.a * fw * 2.0 * reflect_gain, 0.0, 1.0);
	vec3 col = env.rgb * ea + lit * (1.0 - ea);

	ALBEDO = gamma_correct ? srgb_to_linear(col) : col;
	ALPHA = glass_opacity;
}
