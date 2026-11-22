shader_type canvas_item;
render_mode blend_disabled;

// "Diffuse"/paint map of the MC3 car paint (256x256 render target).
//
// Recreates mcCarMetallicPaint::GenSpecular -> RenderHighlights -> DrawHilight:
//   1. fill the target with the base paint colour (gradient stop 1)
//   2. for every light, draw a glow sprite at the map position of the normal that
//      would reflect that light to the viewer, blended SrcAlpha + One (additive).
//
// The glow sprite is the 8-bit radial image from SetupImage (index = distance from
// the centre, 0..255) looked up in the palette built by MakeGradient:
//   colour = mix(colour A, colour B, t)     alpha = 1 - t        (t = radial distance 0..1)

const int MAX_LIGHTS = 12;

uniform vec4 color_a = vec4(1.0, 0.63, 0.18, 1.0); // gradient stop 0 (highlight colour)
uniform vec4 color_b = vec4(0.21, 0.10, 0.03, 1.0); // gradient stop 1 (base paint colour)
uniform float gradient_start = 0.0;                 // position of stop 0 (0..1)

// 12x1 RGBAF texture, one texel per light:
//   xy = sprite centre (map UV), z = sprite half-size (map UV), w = sprite vertex alpha
uniform sampler2D light_data : filter_nearest, repeat_disable;
uniform int light_count = 0;

void fragment() {
	vec3 col = color_b.rgb;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) {
			break;
		}
		vec4 L = texelFetch(light_data, ivec2(i, 0), 0);
		float t = clamp(length((UV - L.xy) / max(L.z, 0.0001)), 0.0, 1.0);
		float g = clamp((t - gradient_start) / max(1.0 - gradient_start, 0.0001), 0.0, 1.0);
		vec3 palette = mix(color_a.rgb, color_b.rgb, g);
		float alpha = (1.0 - t) * L.w;
		col += palette * alpha; // SrcAlpha, One
	}
	COLOR = vec4(min(col, vec3(1.0)), 1.0);
}
