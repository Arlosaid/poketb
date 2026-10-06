shader_type canvas_item;
// Destello: mezcla el sprite hacia un color de la paleta (PAPER por defecto).
// Se usa al recibir un golpe, al capturar y en la evolución.

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color = vec3(1.0, 0.98, 0.94);

void fragment() {
	vec4 c = COLOR;
	COLOR = vec4(mix(c.rgb, flash_color, amount), c.a);
}
