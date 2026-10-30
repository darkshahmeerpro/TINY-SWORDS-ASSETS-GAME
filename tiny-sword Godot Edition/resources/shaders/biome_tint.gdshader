shader_type canvas_item;

// Tints terrain by sampling a low-resolution biome colour field in world space.
// One texel covers several cells, so linear filtering fades neighbouring biomes
// into each other instead of stepping tile by tile.

uniform sampler2D biome_field : filter_linear, repeat_disable;
uniform vec2 field_origin = vec2(0.0);
uniform vec2 field_span = vec2(1.0);
uniform float strength : hint_range(0.0, 1.0) = 1.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 uv = clamp((world_pos - field_origin) / field_span, vec2(0.0), vec2(1.0));
	vec3 tint = texture(biome_field, uv).rgb;
	COLOR.rgb *= mix(vec3(1.0), tint, strength);
}
