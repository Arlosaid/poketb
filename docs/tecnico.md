# Notas técnicas

## Ventana
- La ventana principal es borderless, transparente por píxel y `no_focus`. Ya no es topmost: se comporta como una app normal y queda detrás de otros programas.
  - `DesktopWindow` la coloca encima del área de trabajo (`screen_get_usable_rect`), con el ancho de la pantalla y un alto lógico de 96 px a escala entera.
  - Cada 2 s comprueba la geometría, mantiene sin botón de barra las ventanas extra (panel de pelea) y detecta apps a pantalla completa. La principal sí tiene botón de barra, con `assets/ui/icon.png` (y `icon.ico` para los accesos directos).
- Renderizado pixel-perfect con `content_scale_mode=viewport` + `stretch=integer`. El tamaño lógico es `ancho_pantalla/escala × 96`.

## Clic a través (crítico)
- `Passthrough` (autoload) compara cada frame `DisplayServer.mouse_get_position()` con los `get_click_rect()` de los nodos registrados. Llama a `DesktopNative.set_click_through()` solo cuando el estado cambia.
- `capture_count > 0` mantiene la ventana clicable mientras se arrastra algo.
- No se usa `window_set_mouse_passthrough`: en Windows usa `SetWindowRgn`, que recorta el render.

## GDExtension `DesktopNative` (`native/`)
| Método | Win32 |
|---|---|
| `set_click_through(wid, on)` | `WS_EX_LAYERED` + `WS_EX_TRANSPARENT` (más `SetLayeredWindowAttributes(255)` la primera vez) |
| `hide_from_taskbar(wid)` | `WS_EX_TOOLWINDOW`, sin `WS_EX_APPWINDOW`, más `ITaskbarList::DeleteTab` |
| `reassert_topmost(wid)` | `SetWindowPos(HWND_TOPMOST, SWP_NOACTIVATE)` |
| `no_activate_on_click(wid)` | Subclase (`SetWindowSubclass`): `WM_MOUSEACTIVATE` → `MA_NOACTIVATE`; quita `WS_EX_NOACTIVATE`. Se llama cada 2 s desde `DesktopWindow._maintain` (idempotente). |
| `get_idle_seconds()` | `GetLastInputInfo` |
| `get_taskbar_info()` | `SHAppBarMessage(ABM_GETTASKBARPOS/ABM_GETSTATE)` |
| `is_fullscreen_app_active()` | `SHQueryUserNotificationState` |
| `get_foreground_app()` | `GetForegroundWindow` → `GetWindowThreadProcessId` → `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` → `QueryFullProcessImageNameW`; devuelve solo el nombre del .exe en minúsculas ("" si es el propio juego). Nunca lee títulos. |
| `get_power_status()` | `GetSystemPowerStatus` → `{has_battery, percent, charging}` |

Para compilar hace falta VS 2022 Build Tools (C++) y `pip install scons`. Desde `native/`:
`scons platform=windows target=template_debug` (y `template_release`). La primera compilación de godot-cpp tarda unos 4 min.

## Pipeline de sprites (Fase 9: las 1025 especies)
1. `tools/fetch_sprites.py`: clon parcial + sparse checkout de SpriteCollab en `~/.cache/spritecollab` (solo los archivos raíz de cada especie: `AnimData.xml`, hojas `-Anim`/`-Shadow`, retratos y créditos; ~330 MB fuera del proyecto). Las especies sin forma base pero con una forma alternativa usan `tools/sprite_forms.json`. Genera `data/sprite_credits.json`.
2. `tools/pack_sprites.py`: por cada especie de `data/pokemon_roster.json` escribe en `pokemon/species/<nombre>/`:
   - `sheet.png`: los cuadros de las animaciones de `WANTED`, recortados, **sin repetidos** y empacados por estantes (PNG indexado);
   - `portraits.png`: tira de retratos de 40x40 (solo las emociones que usa el juego);
   - `meta.json`: por animación `fw`, `fh`, `frames`, `dirs`, `durations`, `loop`, `cells[dir][cuadro]` (índice de celda), `ground`, `bbox`, `rush`/`hit`/`return`, `length_ticks` y `shadow`; además `cells` (x, y, w, h, margen x, margen y), `alias` (animación lógica → real, de `ALTERNATIVES`) y `portraits` (emoción → índice en la tira).
   Escribe `data/sprite_index.json` (especies con arte) y `tools/import_log.txt`. Tarda ~40 s con varios procesos.
3. `godot --headless --path . --import`: importa las hojas nuevas (y registra los `class_name` nuevos).

En el juego, `PokemonActor.frames_for(especie)` arma el `SpriteFrames` en memoria: cada cuadro es un `AtlasTexture` con `region` (el recorte) y `margin` (devuelve el tamaño del cuadro PMD, así el ancla no cambia). Guarda en caché los 40 más recientes. `PokemonActor.portrait(especie, [emociones])` devuelve el retrato como `AtlasTexture`.

984 de 1025 especies tienen sprites en SpriteCollab. Las 41 restantes (sobre todo de las Gen 5–9; la lista sale en `tools/fetch_sprites.py`) existen en los datos, pero no aparecen en el mundo (`SpeciesDB.has_sprite`): no salen en rutas y una evolución hacia ellas espera. Cuando SpriteCollab las dibuje, basta con volver a correr los pasos 1–3 y `tools/gen_routes.py`.

## Datos canon
`tools/fetch_pokeapi.py` (1025 especies, 8 hilos, caché en `tools/.cache/pokeapi`) genera `data/pokemon_roster.json`, `abilities.json`, `data/species.json`, `moves.json`, `types.json`, `natures.json`, `berries.json` y `growth.json`. Cachea las respuestas en `tools/.cache/pokeapi`. Los learnsets usan el primer version group disponible entre: scarlet-violet, sword-shield, ultra-sun-ultra-moon, sun-moon y x-y.

## Validación
- `--scenario=still` deja a Charmander quieto en x lógica 100 (en pantalla: x≈180–218, y≈984–1034 a x2) y guarda `shots/p1_still.png`.
- `tools/probe.ps1 -Action hit|move|click|find` dice qué ventana recibiría el clic, mueve el cursor y hace clic, o lista los estilos de la ventana de Godot.

## Fondos y día/noche
- `world/Backdrop.gd` arma el cielo (`world/sky.gdshader`), las capas de `data/biomes/<id>.json` (Sprite2D con `region` y repetición) y `Ambient` (polen, luciérnagas, hojas).
  - Las capas comparten un `ShaderMaterial` (`world/palette_lut.gdshader`) que busca el índice de paleta más cercano y lo re-mapea con la LUT de `DayNight`.
- `world/DayNight.gd` traduce la hora a dos fases + `blend`, configura el cielo y da `sprite_tint()` para los Pokémon.
- `--scenario=gallery` guarda en `shots/`:
  - `p2_anim_*.png`: todas las especies en cada animación;
  - `p2_strip_<bioma>_<hora>.png`: el panel a las 6, 12, 18 y 23 h;
  - `p2_ui.png`: el tema de UI.

## UI
- `ui/UiTheme.gd` construye el `Theme` en código, con la fuente sin antialiasing y StyleBoxTexture 9-patch. Variaciones de tipo: `DialogPanel`, `DialogLabel` y `Slot`.

## Modelo y mascotas
- `pokemon/SpeciesDB.gd` da acceso de solo lectura a `data/*.json`. `pokemon/PokemonInstance.gd` calcula los stats canon (EV 0), la EXP por curva, los movimientos (los últimos 4 de daño), la evolución, la amistad, la saciedad, la energía y los sabores descubiertos.
- `core/Roster.gd` (en `Game.roster`) guarda los miembros, el equipo, el compañero y las bayas, y aplica `tick()` (necesidades), `pet()` y `feed()`.
- `pet/HomeArea.gd` sincroniza quién está en casa. `pet/PetBrain.gd` es la máquina de estados de cada mascota.
- `ui/Bubble.gd` (retrato con alternativas de emoción), `ui/BerryMenu.gd` y `ui/Fx.gd` (corazones, zzz, polvo, destellos, texto flotante).
- Para probar: `Passthrough.fake_mouse` y `Game.forced_idle` simulan el cursor y la inactividad en los escenarios.

## Pelea
- `battle/BattleMath.gd` reúne las fórmulas puras: daño Gen 5+, elección de movimiento, EXP Gen 7, captura Gen 5+ y tablas ponderadas.
- `battle/BattleController.gd` es la máquina de estados (IDLE, WALK, BATTLE, RESTING). Las secuencias son corrutinas que `_epoch` cancela al cambiar de modo. La señal `event(kind)` marca los momentos clave.
- HUD: `InfoChip` (nombre, PS y EXP), `RouteProgress` (pestaña sobre el marco), `BattleLog` (diálogo encima del panel) y `ui/HpBar.gd`.
- Las rutas se definen en `data/routes/*.json`: tablas de día y de noche, rango de niveles, secciones de bioma, jefe, captura y botín de bayas.

## Guardado, offline y PC
- `core/SaveManager.gd` maneja `save(age)` y `load_game()`, que devuelve los segundos que pasaron. `Main._notification(WM_CLOSE_REQUEST)` guarda al salir.
- `battle/OfflineSim.gd` (simulación) y `ui/OfflineSummary.gd` (resumen).
- `ui/PCWindow.gd` (Window nativa con la misma escala entera) y `ui/MonCell.gd` (casilla con drag & drop). `Game.shot_window()` captura ventanas secundarias.

## Progresión (Fase 7)
- `core/Progression.gd`: datos y fórmulas puras (árbol, objetos, costos, monedas, EXP, sorteo de objetos). Lee `data/skill_tree.json` y `data/items.json`.
- Estado: `Roster` guarda `gold`, `skills` (nodo → nivel) y `bag` (`"objeto:nivel"` → cantidad); cada `PokemonInstance` guarda `doses`, `move_mastery`, `held` y `custom_moves`. Las compras son métodos de `Roster` (`buy_skill`, `buy_vitamin`, `buy_mastery`, `equip`, `merge`...). `Roster.fx(efecto)` es la suma cacheada de un efecto del árbol. La señal `wallet_changed` avisa de monedas y mochila sin reconstruir al equipo en ruta.
- `PokemonInstance.stat()` suma árbol, objetos y vitaminas **solo si `uid != 0`** (los salvajes usan las stats canon puras). Por eso `OfflineSim` y `BattleController` crean los salvajes con `uid = 0`, y solo reciben uid al capturarse.
- `BattleMath.attack` aplica maestría, daño y crítico del árbol y de objetos. La captura usa el parámetro `ball` que ya existía.
- Interfaz: `ui/TrainPage.gd`, `ui/BagPage.gd`, `ui/TreePage.gd` (solo reconstruyen la pestaña visible), `ui/ItemCell.gd`, `ui/MonPicker.gd`, `ui/Pips.gd`, `ui/Widgets.gd`.
- El guardado sigue en `version` 1: los campos nuevos tienen valor por defecto, así que las partidas anteriores cargan sin cambios.
- Íconos de objetos, vitaminas y moneda: `tools/gen_ui.py` → `assets/ui/items.png`, `vitamins.png`, `coin.png`.
- Tras agregar `class_name` nuevos hay que correr `godot --headless --path . --import` una vez para actualizar el caché de clases.
- `--scenario=growth` compra mejoras, comprueba el daño con y sin bonos y el guardado ida y vuelta, y saca las capturas `p7_pc_*`.

## Botón de la PC
- `ui/PCButton.gd`: Poké Ball clicable (registrada en `Passthrough`) que abre la PC. Hay una en la casa (`Main.pc_button`, a la izquierda sobre la barra) y otra en el panel de pelea (`BattleController.pc_button`, abajo a la derecha). Al pasar el cursor da un saltito y muestra "PC".
- `--scenario=hold` no hace nada hasta `--autoquit`: sirve para pruebas externas (estilos de ventana, barra de tareas).

## Mascotas vivas (Fase 8)
- `pet/PetBrain.gd`: máquina de estados por mascota (IDLE, WANDER, SIT, LAY, SLEEP, WAKE, LOOK, PETTED, EAT, DRAG, FALL, ACT, CHASE, SOCIAL, FOLLOW, AWAY). `_choose_next` pondera según el rasgo (`Personality.weights`), la hora (y si es nocturno), el cansancio, la diversión, la salud y la app activa (`home.calm`, `home.watching`, `home.music`).
- Interacciones: clic = caricia (y `Roster.cuddle_heal` si está herido); 4 clics en 1.3 s = cosquillas; 5 cambios de dirección del mouse encima en 1.6 s = rascar; mouse quieto 1.2 s encima = `PetCard`; arrastrar y soltar = lanzar con la velocidad del cursor (los voladores planean); clic derecho = `ActionBar`.
- `pet/HomeArea.gd`: coordina la pelota (`ToyBall`), los juegos entre mascotas (`start_social`: saludo, persecución, siesta juntos; elige compañero según `Roster.bonds`), los vuelos (`FlightWindow`) y las reacciones de `PcSense`.
- `pet/PcSense.gd`: sondeo cada 3 s de la app activa (`data/apps.json`), el regreso tras ≥5 min fuera, la racha de uso (recordatorio de pausa), la madrugada y la batería. En los escenarios no sondea; las señales se disparan a mano.
- `pet/Personality.gd`: característica canon → rasgo (`data/characteristics.json`, `data/personality.json`).
- UI: `ui/Emote.gd` (globito con ícono de 7x7, no clicable), `ui/Bubble.gd` (`Bubble.say`, una línea, no clicable), `ui/ActionBar.gd`, `ui/BerryMenu.gd` (compacto) y `ui/PetCard.gd`. `PokemonActor.attached(key)` devuelve el cartel activo ("bubble", "emote" o "card"); solo hay uno a la vez.
- Ajustes del jugador en `Game.settings` (`topmost`, `flights`, `app_react`, `wellbeing`), guardados en `save.json` y editables desde la bandeja. `Game.hide_pets(min)` esconde las mascotas.
- Escenario: `--scenario=pet` genera p3_home, p3_sleep y p8_* (caricia, acciones, bayas, ficha, comer, cosquillas, rascar, mimos que curan, emociones, pelota, saludo, voltereta, pausa, ánimo, video y vuelo).

## Movimientos con animación propia (Fase 9)
- `tools/gen_move_fx.py` aplica `data/move_fx_rules.json` a los 692 movimientos de `data/moves.json` y escribe `data/move_fx.json`: por movimiento, `body` (animación lógica del cuerpo: Punch, Kick, Bite, Claw, Chop, Slam, Head, Swing, Spin, Multi, Quick, SpAttack, Sound, Shock, Rumble, Rise, Flap, Sink, Dance…), `style`, `part` (partícula) y `hits`. Las reglas buscan palabras en el nombre (punch, fang, beam, storm…), usan datos canon (`meta.drain`, `max_hits`, `target`, `category`) y tienen `overrides` por movimiento.
- `battle/MoveFx.gd` dibuja 30 estilos: contact, punch, kick, slam, bite, slash, swing, spin, vine, projectile, barrage, beam, spray, bolt, rain, rise, quake, wave, wind, sound, psychic, drain, explosion, vanish, dive_bomb, aura, heal, status, shield y field. Los colores salen del tipo del movimiento (`type_colors`: claro, medio y oscuro de la paleta) y las partículas, de `assets/ui/fx_parts.png` (22 formas × 18 tipos, generado por `gen_ui.py → fx_parts()`). Los trazos (rayos, ondas, garras, colmillos) se dibujan en `_draw` a la resolución lógica, sin antialias.
- Uso: `MoveFx.create(padre, atacante, punto, movimiento, defensor, chico)`, `fx.start()` y `await fx.wait_impact()`. En la pelea, `BattleController._attack` aplica el daño en el impacto, y `_stage_shake(px)` sacude el escenario. En casa (`small = true`) hay menos partículas y no hay sacudidas.
- `--scenario=moves` prueba un movimiento de cada estilo y guarda `shots/p9_<estilo>_battle.png` (y `_a` a mitad del efecto).

## Rutas para todas las especies (Fase 9)
- `tools/gen_routes.py` genera de `ruta_2` a `ruta_13` (y agrega `next` a la Ruta 1). Cada especie con sprite va a una sola ruta según sus tipos y su nivel mínimo (forma básica: 2; evolución por nivel: su nivel canon; por piedra, intercambio o amistad: 14 más que su forma previa). Los legendarios y singulares están en el Santuario Legendario (Nv. 60–80, jefe Arceus). Las entradas llevan `min_level`, y `BattleController.wild_level` nunca baja de él.
- Al vencer al jefe se pasa sola a la ruta `next` (`BattleController.load_route`). El guardado ya guardaba el id de la ruta; ahora `SaveManager.load_game` lo carga.
- Biomas nuevos: `playa`, `montana`, `nieve`, `volcan` y `pantano` (`data/biomes/*.json`, con los mismos generadores y otros colores).
- Evolución por amistad: `PokemonInstance.evolution_ready` también acepta las de `evolutions` con `trigger: level-up` y `happiness` (y `time` de día o de noche). Las de piedra e intercambio están en los datos, pero todavía no se usan.

## Mascotas por tipo, entrenamiento y vuelos (Fase 9)
- `pet/TypeAct.gd` ejecuta las acciones de `data/pet_types.json` (ver `docs/mascotas.md`).
- `PetBrain.train()` y `perform_move()` usan `MoveFx` en chico; `HomeArea.run_spar()` es el combate de práctica.
- Vuelos: `HomeArea` tiene un grupo de `FlightWindow` (hasta `flight.max_fliers` a la vez) y arma rutas que cruzan toda la pantalla, con rizos y pausas. `FlightWindow` ajusta su tamaño al Pokémon y tiene estilos (`bird`, `bug`, `dragon`, `float`).
- `--scenario=types` saca `p9_types*`, `p9_train`, `p9_spar` y `p9_fly_<estilo>`.
