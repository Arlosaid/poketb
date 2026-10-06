shader_type canvas_item;
// Cielo pixel art: degradado por bandas con tramado Bayer 4x4 entre colores de la
// paleta (nunca degradados suaves fuera de ella), sol/luna según la hora y estrellas.
// Mezcla dos fases del día (a → b) con tramado según `blend`.

uniform vec2 size = vec2(376.0, 56.0);       // px lógicos del rectángulo
uniform vec3 stops_a[4];                      // arriba → abajo, fase a
uniform vec3 stops_b[4];                      // fase b
uniform float blend : hint_range(0.0, 1.0) = 0.0;
uniform float horizon = 0.78;                 // fracción de alto donde termina el degradado
uniform vec2 sun_pos = vec2(0.7, 0.3);        // en fracción del rectángulo
uniform float sun_kind = 0.0;                 // 0 = sol, 1 = luna
uniform vec3 sun_core;
uniform vec3 sun_rim;
uniform float star_amount = 0.0;              // 0..1
uniform vec3 star_a;
uniform vec3 star_b;
uniform float time_s = 0.0;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float bayer(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	return (BAYER[y * 4 + x] + 0.5) / 16.0;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 gradient(vec3 s0, vec3 s1, vec3 s2, vec3 s3, float t, vec2 px) {
	// t: 0 arriba, 1 en el horizonte. Tres tramos con transición tramada.
	float f = clamp(t, 0.0, 1.0) * 3.0;
	float seg = floor(min(f, 2.999));
	float local = f - seg;
	// la transición tramada ocupa la mitad final de cada tramo
	float k = smoothstep(0.45, 1.0, local);
	bool next = bayer(px) < k;
	if (seg < 0.5) return next ? s1 : s0;
	if (seg < 1.5) return next ? s2 : s1;
	return next ? s3 : s2;
}

void fragment() {
	vec2 px = floor(UV * size);
	float t = px.y / (size.y * horizon);
	vec3 ca = gradient(stops_a[0], stops_a[1], stops_a[2], stops_a[3], t, px);
	vec3 cb = gradient(stops_b[0], stops_b[1], stops_b[2], stops_b[3], t, px);
	vec3 col = (bayer(px + vec2(2.0, 1.0)) < blend) ? cb : ca;

	// estrellas (solo arriba), parpadeo lento
	if (star_amount > 0.0 && t < 0.85) {
		float h = hash(px);
		if (h > 1.0 - 0.012 * star_amount) {
			float tw = sin(time_s * 1.3 + h * 60.0);
			if (tw > -0.3) col = (h > 1.0 - 0.004 * star_amount) ? star_b : star_a;
		}
	}

	// sol o luna: disco pixelado con borde
	vec2 c = floor(sun_pos * size) + 0.5;
	float r = 4.0;
	vec2 d = px + 0.5 - c;
	float dist = length(d);
	if (dist <= r + 0.2) {
		col = (dist > r - 1.0) ? sun_rim : sun_core;
		if (sun_kind > 0.5) {
			// luna creciente: muerde el disco con otro círculo desplazado
			vec2 d2 = d - vec2(-2.0, -1.0);
			if (length(d2) <= r - 0.5) col = ca;
		}
	} else if (sun_kind < 0.5 && dist <= r + 2.2 && bayer(px) < 0.5) {
		col = sun_rim; // halo tramado del sol
	}
	COLOR = vec4(col, 1.0);
}
