shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4  shield_color  : source_color = vec4(0.0, 0.7, 1.0, 0.85);
uniform float intensity     : hint_range(0.0, 5.0)  = 1.5;
uniform float hex_scale     : hint_range(1.0, 20.0) = 6.0;
uniform float pulse_speed   : hint_range(0.1, 5.0)  = 1.5;
uniform float wave_speed    : hint_range(0.1, 10.0) = 3.0;


vec2 hex_center(vec2 p) {
	vec2 r = vec2(1.0, 1.732);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	return dot(a, a) < dot(b, b) ? a : b;
}


void fragment() {
	// UV centré : -1 → +1
	vec2  uv         = UV * 2.0 - 1.0;

	// Forme ovale — supprime les pixels hors du bouclier
	float shape_dist = length(uv * vec2(0.85, 1.0));
	float shape      = 1.0 - smoothstep(0.75, 1.0, shape_dist);
	if (shape < 0.001) { discard; }

	float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;

	// Grille hexagonale
	vec2  hex      = hex_center(UV * hex_scale);
	float hex_d    = length(hex);
	float hex_line = 1.0 - smoothstep(0.04, 0.14, hex_d);
	float hex_glow = exp(-hex_d * 10.0) * 0.25;

	// Bord extérieur lumineux (suit la forme ovale)
	float edge = smoothstep(0.45, 0.85, shape_dist);

	// Vague d'énergie animée
	float wave = pow(sin(UV.y * 10.0 - TIME * wave_speed) * 0.5 + 0.5, 5.0) * 0.35;

	float brightness = (hex_line * 0.65 + hex_glow + edge * 0.9 + wave + pulse * 0.12) * shape;

	// Légère variation holographique verticale
	vec3 holo = shield_color.rgb + vec3(-0.05, 0.05, 0.15) * (UV.y - 0.5);

	ALBEDO   = holo;
	ALPHA    = clamp(brightness * intensity * shield_color.a, 0.0, 1.0);
	EMISSION = holo * (hex_line + edge * 0.6 + pulse * 0.08) * intensity;
}
