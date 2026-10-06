# Taskbar Pokémon — guía del proyecto

Juego de escritorio **personal y no comercial**: un idle tipo Taskbar Hero más una mascota de escritorio Pokémon, que vive en una ventana transparente sobre la barra de tareas de Windows. **El arte es la prioridad número uno.**

Documentos (mantenerlos al día al terminar cada fase):
- `docs/diseno.md`: diseño del juego.
- `docs/arte.md`: dirección de arte y **paleta de 32 colores** (obligatoria).
- `docs/tecnico.md`: arquitectura, ventana nativa, pipelines.
- `docs/decisiones.md`: registro de decisiones. Cuando haya que decidir algo sin preguntar, anotarlo aquí.

## Stack
- Godot **4.7.2-stable**, con GDScript y el renderer `gl_compatibility`.
  - Editor: `C:\Users\Alonso\Desktop\Godot_v4.7.2-stable_win64.exe`.
  - Consola para logs: `..._console.exe`.
- GDExtension propia en `native/` (C++, godot-cpp 4.5 como submódulo y SCons). Expone el singleton `DesktopNative` para clic a través real, ocultar el ícono de la barra de tareas, la inactividad del sistema, info de la barra y detección de pantalla completa. La DLL compilada queda en `addons/desktop_native/bin/`.
- Python 3.12 para las herramientas de desarrollo en `tools/`. Correr siempre con `python -I`.

## Comandos
Para jugar: doble clic en `Jugar-Pokemon.bat` (en el Escritorio) o en `Jugar.bat` (en el proyecto). No hay `.exe` exportado: faltan las plantillas de exportación de Godot (~1 GB, Editor → Administrar plantillas de exportación).
```bash
# Compilar la extensión nativa (desde una consola con el entorno de MSVC, ver docs/tecnico.md)
cd native && scons platform=windows target=template_debug && scons platform=windows target=template_release
# Datos y assets (solo en desarrollo; el juego NO usa internet)
python -I tools/fetch_sprites.py       # sparse checkout de SpriteCollab → assets/raw/spritecollab + data/sprite_credits.json
python -I tools/fetch_pokeapi.py       # PokeAPI → data/*.json
python -I tools/gen_ui.py              # marcos 9-patch, íconos, paleta → assets/ui
python -I tools/gen_backgrounds.py     # capas de parallax → assets/bg (lee data/biomes/*.json)
python -I tools/gen_credits.py         # CREDITS.md desde data/sprite_credits.json
"<godot_console>" --headless --path . --script res://tools/import_sprites.gd   # AnimData.xml → SpriteFrames
# Correr el juego
"<godot_console>" --path . -- [--debug] [--scenario=still|pet|battle|gallery] [--autoquit=SEG]
python -I tools/compose_shot.py shots/<captura>.png --x0 0 --x1 400 --zoom 3
```

## Reglas no negociables
1. **No estorbar el trabajo.** Las zonas vacías siempre dejan pasar el mouse: solo los sprites y la UI registrados en `Passthrough` son clicables. La ventana usa `no_focus`, así que nunca roba el foco.
2. **Consumo bajo.** 30 FPS en combate o interacción (`keep_awake`), 20 en paseos (`keep_ambient`), 10 en reposo y 5 con una app a pantalla completa. No hacer trabajo por frame que pueda ir en un timer.
3. **Pixel-perfect.** Escala entera, filtro Nearest, sin escalas ni rotaciones fraccionarias del pixel art.
4. **Paleta cerrada.** Usar los colores de `core/Palette.gd`. Nunca hex sueltos en el código ni en las escenas.
5. **Datos separados de la lógica.** Especies, movimientos, rutas, biomas y bayas viven en `data/*.json`. Agregar contenido no debe requerir tocar código.
6. **Canon.** Stats, tipos, efectividades, naturalezas, sabores, curvas de EXP y niveles de evolución salen de PokeAPI (copiados localmente). No inventar números canon.
7. **Sin castigos crueles.** Ningún Pokémon muere ni se escapa.
8. **Licencias.** SpriteCollab es CC BY-NC 4.0: cada sprite usado debe tener crédito en `CREDITS.md` y en la pantalla de créditos. Toda fuente o asset de terceros va documentado con su licencia.

## Convenciones
- Carpetas por sistema: `core/`, `pokemon/`, `battle/`, `pet/`, `ui/`, `world/`, `data/`, `tools/`, `native/`.
- GDScript sigue la guía de estilo oficial (snake_case, `class_name` en PascalCase, tipado estático siempre que se pueda). Los identificadores van en inglés; los comentarios y textos visibles, en español.
- Las animaciones de Pokémon se llaman `"<Anim>_<dir>"`, con dir ∈ {S, SE, E, NE, N, NW, W, SW} (orden de filas de PMD: Down, DownRight, Right, UpRight, Up, UpLeft, Left, DownLeft). Para pedirlas se usa `PokemonActor.play_anim(name, dir)`, que aplica las alternativas.
- Todo lo que sea clicable implementa `get_click_rect() -> Rect2` (en coordenadas del viewport) y se registra con `Passthrough.register(self)`.
- Para tiempos de juego se usa `Game.clock` (respeta la pausa y la velocidad x10 de depuración), nunca `Time` directamente.

## Verificación al cerrar una fase
1. Correr con el ejecutable de consola, guardar el log y confirmar que no hay `ERROR`/`SCRIPT ERROR`.
2. Sacar capturas **solo del viewport del juego** (`Game.shot()` en los `--scenario`, que las guarda en `shots/`), componerlas sobre un escritorio neutro con `tools/compose_shot.py` y **mirarlas**. Corregir lo que se vea feo antes de dar la fase por lista. **Nunca capturar el escritorio real**, porque saldrían las ventanas privadas del usuario. El clic a través se valida con `tools/probe.ps1` (`WindowFromPoint`, que no genera imágenes).
3. Actualizar `docs/` y hacer un commit.

## Estado
- [x] Fase 0: andamiaje, documentación, compilador.
- [x] Fase 1: ventana nativa y passthrough (validado: clic a través, sin ícono en la barra, clic sobre el sprite llega al juego).
- [x] Fase 2: pipeline de arte (importador, paleta, fuente, marcos, fondos con parallax, cielo según la hora). `--scenario=gallery` genera las capturas de revisión.
- [x] Fase 3: modo mascota (`--scenario=pet` genera las capturas p3_*).
- [x] Fase 4: modo pelea (`--scenario=battle`: encuentro, golpe, captura, nivel, evolución, jefe, debilitado; capturas p4_*).
- [x] Fase 5: PC, guardado y offline (`--scenario=save_write` y luego `--scenario=save_load`; capturas p5_*).
- [x] Fase 6: pulido y créditos (`--scenario=showcase`: vista de conjunto de día y de noche).

## Ideas para después del MVP
- Ruta 2 "Bosque Verde" (solo es un JSON de ruta y un bioma).
- Movimientos de estado y objetos.
- Sonidos suaves enganchados a `BattleController.event`.
- Panel de pelea redimensionable desde la PC.
