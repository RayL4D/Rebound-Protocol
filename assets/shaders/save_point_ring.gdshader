shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4  ring_color  : source_color = vec4(0.0, 0.85, 1.0, 0.55);
uniform float inner_ratio : hint_range(0.0, 1.0) = 0.68;
uniform float pulse       : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2  uv   = UV * 2.0 - 1.0;
	float dist = length(uv);
	float ring  = step(inner_ratio, dist) * step(dist, 1.0);
	float glow  = smoothstep(1.0, inner_ratio, dist) * 0.18;
	float alpha = (ring * ring_color.a + glow) * (1.0 + pulse * 0.35);
	ALBEDO   = ring_color.rgb;
	EMISSION = ring_color.rgb * (1.8 + pulse * 1.2) * ring;
	ALPHA    = clamp(alpha, 0.0, 1.0);
}
