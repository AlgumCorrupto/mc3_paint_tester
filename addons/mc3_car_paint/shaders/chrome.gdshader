shader_type spatial;
render_mode unshaded, cull_back;

// MC3 chrome (drwShaderChrome / drwShaderGarageCarChrome / drwShaderMoreChromeWheel*).
// Verified against the Xbox capture (draw EID 3912, the wheel spokes): mean error 0.005.
//
//   ambient'   = ambient + (1 - ambient) * chrome_ambient_lift        (chrome_color_a, default 0.2)
//   COLOR0.rgb = clamp((ambient' + sum_i max(N.-L_i, 0) * lightColor_i) * chrome_color)
//   uv         = (a * clip.xy + s * nclip.xy) * scale + 0.5           a = 0.8 * 0.25 (SetFresnelParamsChrome)
//   out        = clamp(COLOR0.rgb * envMap(uv).rgb * 2)               (one MODULATE2X stage, second stage is identity)
//
// The envmap is the same 256x256 render target the car paint reflects.

uniform sampler2D env_map : filter_linear, repeat_disable;

uniform vec3 chrome_color = vec3(1.0);
uniform float chrome_ambient_lift = 0.2;

uniform vec3 light_dir0 = vec3(0.63797, -0.50528, -0.58111);
uniform vec3 light_dir1 = vec3(0.0, -0.95783, -0.28735);
uniform vec3 light_dir2 = vec3(-0.57735, -0.57735, -0.57735);
uniform vec3 light_col0 = vec3(0.34036);
uniform vec3 light_col1 = vec3(0.25);
uniform vec3 light_col2 = vec3(0.0);
uniform vec3 ambient = vec3(0.065);

uniform float lookup_scale = 0.64248;
uniform float normal_weight = 0.25;
uniform float env_pos_weight = 0.2;
uniform bool keep_model_scale = false;
uniform bool per_pixel_lookup = false;
uniform float reflect_gain = 1.0;
uniform bool gamma_correct = true;

varying vec2 v_env_uv;
varying vec3 v_color0;
varying vec3 v_nview;
varying vec3 v_pview;

vec2 mc3_uv(vec3 n, vec3 p, mat4 proj) {
	float fx = proj[0][0];
	float fy = abs(proj[1][1]);
	vec2 clip_xy = vec2(fx * p.x, fy * p.y);
	vec2 n_clip = vec2(fx * n.x, fy * n.y);
	return (env_pos_weight * clip_xy + normal_weight * n_clip) * lookup_scale + vec2(0.5);
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

	vec3 amb = ambient + (vec3(1.0) - ambient) * chrome_ambient_lift;
	float d0 = max(dot(nw, -normalize(light_dir0)), 0.0);
	float d1 = max(dot(nw, -normalize(light_dir1)), 0.0);
	float d2 = max(dot(nw, -normalize(light_dir2)), 0.0);
	vec3 light = amb + d0 * light_col0 + d1 * light_col1 + d2 * light_col2;

	v_color0 = clamp(light * chrome_color, 0.0, 1.0);
	v_env_uv = mc3_uv(n, p, PROJECTION_MATRIX);
	v_nview = n;
	v_pview = p;
}

void fragment() {
	vec2 uv = v_env_uv;
	if (per_pixel_lookup) {
		vec3 n = v_nview;
		if (!keep_model_scale) {
			n = normalize(n);
		}
		uv = mc3_uv(n, v_pview, PROJECTION_MATRIX);
	}
	vec3 env = texture(env_map, uv).rgb;
	vec3 col = clamp(v_color0 * env * 2.0 * reflect_gain, 0.0, 1.0);
	ALBEDO = gamma_correct ? srgb_to_linear(col) : col;
}
