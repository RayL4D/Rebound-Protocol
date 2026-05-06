shader_type spatial;
render_mode cull_disabled, unshaded;

uniform vec4 base_color : source_color = vec4(0.0, 0.83, 1.0, 1.0); // #00D4FF
uniform float speed : hint_range(0.1, 5.0) = 2.0;
uniform float distortion : hint_range(0.1, 10.0) = 5.0;

void fragment() {
    // Calcul de la distance au centre
    vec2 center_uv = UV - vec2(0.5);
    float dist = length(center_uv);
    
    // Vortex et animation
    float angle = atan(center_uv.y, center_uv.x);
    float vortex = sin(dist * distortion - TIME * speed + angle);
    
    // Couleur des reflets : On prend la base_color et on l'éclaircit légèrement
    // au lieu d'utiliser du blanc pur.
    vec3 highlight_color = mix(base_color.rgb, vec3(0.5, 1.0, 1.0), 0.5);
    
    // Le masque du cercle est passé de 0.5 à 0.6 pour l'agrandir un peu
    // On garde un bord doux pour l'effet d'énergie
    float circle_mask = smoothstep(0.6, 0.55, dist);
    
    // Mélange des bleus
    vec3 final_color = mix(base_color.rgb, highlight_color, vortex * 0.5 + 0.5);
    
    ALBEDO = final_color;
    ALPHA = circle_mask;
}