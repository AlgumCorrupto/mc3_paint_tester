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
//   colour = palette[t]                     alpha = 1 - t        (t = radial distance 0..1)
// The palette (256x1) is built by the script from the paint type's gradient stops
// (Gloss / Enamel: 2 stops, Metallic / Matte: 2 stops, Pearlescent: 2 stops, ColorShift: several).

const int MAX_LIGHTS = 12;

uniform sampler2D palette : filter_linear, repeat_disable;   // 256x1, index 0 = sprite centre, 255 = edge
uniform vec4 color_b = vec4(0.21, 0.10, 0.03, 1.0);          // last gradient stop = base paint colour (the fill)

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
		vec3 pal = texture(palette, vec2(t * (255.0 / 256.0) + 0.5 / 256.0, 0.5)).rgb;
		float alpha = (1.0 - t) * L.w;
		col += pal * alpha; // SrcAlpha, One
	}
	COLOR = vec4(min(col, vec3(1.0)), 1.0);
}
