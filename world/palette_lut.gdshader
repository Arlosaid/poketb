shader_type canvas_item;
// Re-mapea cada color de la paleta a su variante de la fase del día (amanecer,
// atardecer, noche) usando una LUT de 32x4. Así las capas siguen siendo 100% paleta
// también de noche. Entre fases se mezcla con tramado Bayer (sin colores intermedios).

uniform sampler2D lut : filter_nearest;   // 32 columnas (índice) x 4 filas (fase)
uniform vec3 pal[32];
uniform int row_a = 0;
uniform int row_b = 0;
uniform float blend : hint_range(0.0, 1.0) = 0.0;
uniform float px_scale = 2.0;             // escala de pantalla (para tramar en px lógicos)

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec4 c = COLOR; // textura × color de vértice (sirve para sprites y draw_rect)
	if (c.a < 0.01) discard;
	int best = 0;
	float bd = 1e9;
	for (int i = 0; i < 32; i++) {
		vec3 d = c.rgb - pal[i];
		float dd = dot(d, d);
		if (dd < bd) { bd = dd; best = i; }
	}
	vec2 lp = floor(FRAGCOORD.xy / px_scale);
	int bx = int(mod(lp.x, 4.0));
	int by = int(mod(lp.y, 4.0));
	float th = (BAYER[by * 4 + bx] + 0.5) / 16.0;
	int row = (th < blend) ? row_b : row_a;
	COLOR = vec4(texelFetch(lut, ivec2(best, row), 0).rgb, c.a);
}
