shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4  shield_color    : source_color = vec4(0.0, 0.15, 0.8, 0.85); 
uniform vec4  border_color    : source_color = vec4(0.0, 0.8, 1.0, 1.0);   
uniform vec4  core_color      : source_color = vec4(1.0, 1.0, 1.0, 1.0);   
uniform float intensity       : hint_range(0.0, 10.0) = 4.0;
uniform float hex_scale       : hint_range(1.0, 20.0) = 6.0;
uniform float curvature       : hint_range(-2.0, 2.0) = 0.85;

void vertex() {
	vec2 centered_uv = UV - 0.5;
	float dist_sq = dot(centered_uv, centered_uv);
	VERTEX.z += (0.25 - dist_sq) * curvature;
}

vec2 hex_center(vec2 p) {
	vec2 r = vec2(1.0, 1.73205);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	return dot(a, a) < dot(b, b) ? a : b;
}

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	
	float dist_center = length(uv * vec2(1.0, 1.2));
	float shape = 1.0 - smoothstep(0.80, 0.98, dist_center);
	if (shape < 0.001) { discard; }

	float t = TIME;

	// ─── 1. GÉOMÉTRIE ET RELIEF 3D ──────────────────────────────────────────
	vec2 hex = hex_center(UV * hex_scale);
	vec2 local_uv = UV * hex_scale - hex; // Coordonnées au sein d'une seule tuile
	vec2 abs_hex = abs(hex);
	float hex_dist = max(abs_hex.x, abs_hex.x * 0.5 + abs_hex.y * 0.866025);

	// Découpage de la tuile
	float grout = smoothstep(0.42, 0.50, hex_dist); // Jointures plus larges pour accentuer le relief
	float bevel = smoothstep(0.30, 0.42, hex_dist); // Pente du biseau
	
	// NOUVEAU : Trompe-l'œil 3D (Faux éclairage directionnel)
	// On simule une lumière virtuelle venant d'en haut à gauche (-1.0, 1.0)
	vec2 light_dir = normalize(vec2(-1.0, 1.0));
	
	// On calcule quel côté du biseau fait face à la lumière
	float light_dot = dot(normalize(local_uv), light_dir);
	
	// On sépare la lumière de l'ombre
	float fake_highlight = smoothstep(0.0, 1.0, light_dot) * bevel;
	float fake_shadow = smoothstep(0.0, 1.0, -light_dot) * bevel;

	// ─── 2. ILLUMINATION DES TUILES ─────────────────────────────────────────
	vec2 cell_id = UV * hex_scale - hex;
	float cell_hash = hash21(floor(cell_id * 3.0));
	float tile_flicker = smoothstep(0.85, 1.0, sin(t * (1.5 + cell_hash * 3.0) + cell_hash * 10.0));
	float edge_glow = pow(dist_center, 4.0);

	// ─── 3. COMPOSITION DES COULEURS ────────────────────────────────────────
	
	// 1. Fond de la vitre
	vec3 color = shield_color.rgb * 0.15;

	// 2. Application de l'ombre 3D (assombrit le biseau opposé à la lumière)
	color = mix(color, color * 0.2, fake_shadow * 0.8);

	// 3. Application de la lumière 3D (éclaire le biseau face à la lumière)
	color = mix(color, border_color.rgb * 0.9, fake_highlight);

	// 4. Tuiles clignotantes
	color += border_color.rgb * tile_flicker * 1.5 * (1.0 - grout);

	// 5. Plasma dans les jointures profondes
	color = mix(color, border_color.rgb * 2.5, grout);

	// 6. Surcharge des contours
	color = mix(color, border_color.rgb * 2.0, edge_glow);

	// ─── 4. LUMINOSITÉ FINALE ───────────────────────────────────────────────
	float brightness = 
		  (grout * 2.0)       
		+ (fake_highlight * 1.2) // Le bord éclairé brille !
		+ (tile_flicker * 1.5)
		+ (edge_glow * 1.5);
		
	brightness *= shape;

	EMISSION = color * brightness * intensity;
	ALBEDO = color;
	
	// L'ombre ajoute de l'opacité pour renforcer l'illusion d'un bloc dense
	float alpha_base = brightness + (fake_shadow * 0.5) + 0.1;
	ALPHA = clamp(alpha_base * shield_color.a * shape, 0.0, 1.0);
}