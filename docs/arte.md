# Dirección de arte

## Norte
Un Pokémon Mystery Dungeon acogedor que vive sobre la barra de tareas. Suave, cálido y legible en tamaño chico. Antes que muchas cosas mediocres, pocas cosas bien acabadas. Todo es sutil: el juego acompaña y no grita.

## Reglas de oro
1. **Pixel-perfect.** Filtro Nearest, escala entera (x2/x3/x4 según la pantalla), `snap_2d_transforms_to_pixel` y sin rotaciones ni escalas fraccionarias en el pixel art. Los *squash/stretch* se hacen con escalas enteras o desplazando píxeles, nunca con 1.1x.
2. **Paleta cerrada.** Toda la UI, los fondos, las partículas y los efectos usan solo los 32 colores de abajo (`assets/palette.png`, `core/Palette.gd`). Las excepciones son los sprites y retratos de SpriteCollab, que conservan su color original. La transparencia está permitida (alfa sobre un color de la paleta).
3. **Contornos cálidos.** Nada de negro puro: el contorno más oscuro es `ink` (#2b1d1a).
4. **Luz desde arriba a la izquierda.** Los marcos y botones llevan brillo arriba a la izquierda y sombra abajo a la derecha.
5. **Movimiento con easing.** Siempre `TRANS_SINE`/`TRANS_BACK`/`TRANS_QUAD` y nada lineal en la UI. Duraciones de 0.12–0.35 s.

## Paleta (32 colores)

| # | Nombre | Hex | Uso |
|---|--------|-----|-----|
| 0 | ink | `#2b1d1a` | contornos, texto principal |
| 1 | bark | `#4a3128` | sombras de marcos, texto secundario |
| 2 | wood | `#6e4a35` | borde de paneles |
| 3 | oak | `#9a6b47` | borde interior, troncos |
| 4 | tan | `#c99a65` | sombra de panel crema |
| 5 | sand | `#e8c895` | relleno secundario, camino |
| 6 | cream | `#f6e7c1` | fondo de paneles |
| 7 | paper | `#fffaf0` | brillos, texto sobre oscuro |
| 8 | pine | `#1f3a33` | árboles lejanos de noche, sombra de follaje |
| 9 | forest | `#2f5a3d` | árboles medios |
| 10 | leaf | `#4b8049` | colinas, follaje |
| 11 | grass | `#77ab55` | pasto |
| 12 | sprout | `#a9d16a` | pasto con luz |
| 13 | lime | `#d6ec9a` | brillos de pasto, polen |
| 14 | midnight | `#1b2140` | cielo de noche alto |
| 15 | night | `#2c3a6b` | cielo de noche bajo |
| 16 | dusk | `#45609c` | cielo del atardecer alto, colinas lejanas |
| 17 | sky | `#6b93cf` | cielo de día alto |
| 18 | haze | `#9cc4ec` | cielo de día bajo |
| 19 | mist | `#d2ebf7` | horizonte, nubes |
| 20 | plum | `#5a2238` | sombras cálidas, atardecer alto |
| 21 | berry | `#9c3b4a` | PS bajos, bayas rojas |
| 22 | ember | `#d8584f` | daño, corazones (sombra) |
| 23 | flame | `#f08a5a` | fuego, atardecer |
| 24 | amber | `#f9b860` | EXP, sol, luciérnagas |
| 25 | honey | `#ffe08a` | brillos cálidos, estrellas |
| 26 | lilac | `#8a5a9c` | amanecer, sombras de noche |
| 27 | orchid | `#c48ac8` | amanecer, bayas |
| 28 | blush | `#f2a7b8` | corazones, mejillas |
| 29 | petal | `#ffd4dc` | corazones (brillo) |
| 30 | teal | `#3f8f8f` | PS medios, acentos fríos |
| 31 | mint | `#8fd3c7` | PS altos, curación |

Barras de PS: mint (>50%), amber (20–50%) y ember (<20%), con borde `ink` y fondo `bark`.

## Tipografía
Una sola fuente pixel (ver `docs/decisiones.md` → Fuente) en su tamaño nativo y en múltiplos enteros. Texto `ink` sobre `cream`, o `paper` sobre `bark`, con sombra de 1 px en `tan` cuando va sobre panel claro.

## UI
- Los paneles imitan los menús de PMD: cuerpo `cream`, borde doble (`wood` por fuera y `oak` por dentro), esquinas redondeadas de 2 px y sombra de 1 px en `ink` con 40% de alfa. Se dibujan con `NinePatchRect` a partir de `assets/ui/*.png` (generados por `tools/gen_ui.py` y retocados a mano).
- Los textos de combate van en una cajita de diálogo pequeña, abajo dentro del panel de pelea.
- Las burbujas de la mascota tienen forma de bocadillo, con el retrato de 40x40 dentro de un marco de 1 px.

## Sprites de Pokémon
- Vienen de PMD SpriteCollab, a la misma escala entera que todo lo demás.
- Las sombras son una elipse suave dibujada por nosotros (`ink` con 35% de alfa), con su tamaño según `ShadowSize` de AnimData. No se usa la Shadow.png de PMD como imagen, solo como marcador de ancla.

## Fondos
- El cielo es un shader con degradado por bandas (dithering Bayer 4x4 entre colores de la paleta, sin degradados suaves fuera de la paleta) y sigue la hora real: amanecer 5–8, día 8–17, atardecer 17–20 y noche 20–5.
- Las capas son pixel art procedural generado por `tools/gen_backgrounds.py` y cuantizado a la paleta: colinas lejanas, árboles medios, pasto delantero y flores. Cada bioma define sus colores y siluetas en `data/biomes/*.json`.
- De noche, las capas se tiñen hacia `night`/`lilac` con un shader de *tint* que hace multiplicado por paleta.

## Juice (sutil)
- Números de daño que suben 6 px con easing y se desvanecen. Golpe: *shake* de 1–2 px durante 0.15 s. Corazones `blush`/`petal` al acariciar. "Zzz" en `paper` al dormir.
- Transiciones de paneles: aparecen desde 4 px abajo con alfa 0→1 en 0.2 s.
