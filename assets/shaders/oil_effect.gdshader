shader_type spatial;

uniform vec4 oil_color : source_color = vec4(0.02, 0.02, 0.05, 1.0);
uniform float viscosity : hint_range(0.1, 2.0) = 0.5;

void fragment() {
    // Base noire profonde
    ALBEDO = oil_color.rgb;
    
    // Simulation de reflet irisé (arc-en-ciel typique du pétrole)
    float iridescence = sin(UV.x * 10.0 + TIME * viscosity) * cos(UV.y * 8.0 - TIME * 0.5);
    vec3 rainbow = 0.05 * vec3(sin(TIME), cos(TIME), sin(TIME * 0.5));
    
    // Brillance huileuse (Roughness bas, Specular haut)
    ROUGHNESS = 0.05; 
    SPECULAR = 0.8;
    EMISSION = rainbow * step(0.8, iridescence); // Petits reflets colorés
}

void vertex() {
    // Animation de légère ondulation
    VERTEX.y += sin(TIME * viscosity + VERTEX.x * 2.0) * 0.05;
}