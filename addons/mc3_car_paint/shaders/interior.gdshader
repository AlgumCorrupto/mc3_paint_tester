shader_type spatial;
render_mode unshaded, cull_disabled;

// MC3 interior: a flat, unshaded, pitch black material (the cabin mesh of the car, "black_matte" in the
// converted models). No lighting, no reflection, no texture.

uniform vec3 interior_color = vec3(0.0);

void fragment() {
	ALBEDO = interior_color;
}
