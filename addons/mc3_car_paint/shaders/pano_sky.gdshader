shader_type sky;

// Equirectangular sky with an explicit orientation, matching env_map.gdshader's "match_sky" mode:
//   u = atan(dir.x, -dir.z) / 2pi + 0.5      (looking down -Z = centre of the image)
//   v = acos(dir.y) / pi                     (0 = zenith, 1 = nadir)
// Used as the scene background so that background and car reflections show the same panorama.

uniform sampler2D pano : filter_linear, repeat_enable;
uniform bool use_pano = false;
uniform float brightness = 1.0;
uniform vec3 fallback_color = vec3(0.07, 0.075, 0.085);

void sky() {
	if (use_pano) {
		float u = atan(EYEDIR.x, -EYEDIR.z) / TAU + 0.5;
		float v = acos(clamp(EYEDIR.y, -1.0, 1.0)) / PI;
		COLOR = texture(pano, vec2(u, v)).rgb * brightness;
	} else {
		COLOR = fallback_color;
	}
}
