shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4  ring_color  : source_color = vec4(0.0, 0.85, 1.0, 0.55);
uniform float inner_ratio : hint_range(0.0, 1.0) = 0.68;
uniform float pulse       : hint_range(0.0, 1.0) = 0.0;
uniform float rotation_speed : hint_range(-5.0, 5.0) = 1.5;

void fragment() {
	vec2  uv   = UV * 2.0 - 1.0;
	float dist = length(uv);
	
	// Anneau de base
	float ring  = step(inner_ratio, dist) * step(dist, 1.0);
	
	// Création des tirets/segments rotatifs
	float angle = atan(uv.y, uv.x);
	float segments = sin(angle * 12.0 + TIME * rotation_speed);
	
	// On coupe l'anneau avec les segments (0.0 ou 1.0)
	ring *= step(0.0, segments);
	
	// Halo doux autour (glow)
	float glow  = smoothstep(1.0, inner_ratio, dist) * 0.18;
	
	float alpha = (ring * ring_color.a + glow) * (1.0 + pulse * 0.35);
	
	ALBEDO   = ring_color.rgb;
	// On booste l'émission sur les segments pour que ça flashe
	EMISSION = ring_color.rgb * (3.0 + pulse * 2.0) * ring; 
	ALPHA    = clamp(alpha, 0.0, 1.0);
}