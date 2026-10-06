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
| `get_idle_seconds()` | `GetLastInputInfo` |
| `get_taskbar_info()` | `SHAppBarMessage(ABM_GETTASKBARPOS/ABM_GETSTATE)` |
| `is_fullscreen_app_active()` | `SHQueryUserNotificationState` |

Para compilar hace falta VS 2022 Build Tools (C++) y `pip install scons`. Desde `native/`:
`scons platform=windows target=template_debug` (y `template_release`). La primera compilación de godot-cpp tarda unos 4 min.

## Pipeline de sprites
1. `tools/fetch_sprites.py`: sparse checkout de SpriteCollab en `~/.cache/spritecollab`. Copia la forma base a `assets/raw/spritecollab/` y genera `data/sprite_credits.json`.
2. `godot --headless --path . --import`: importa los PNG. Es necesario además para que Godot registre los `class_name` nuevos.
3. `godot --headless --path . --script res://tools/import_sprites.gd` lee AnimData.xml y genera `pokemon/species/<name>/frames.res` + `meta.json`. Las alternativas quedan en `tools/import_log.txt`.

`meta.json` por animación guarda:
- `fw`, `fh`, `frames`, `dirs` (1 u 8);
- `ground`: centro del marcador de sombra respecto al centro del cuadro;
- `bbox`: píxeles opacos respecto al suelo;
- `rush`, `hit`, `return` y `length_ticks` (a 60 fps).

## Datos canon
`tools/fetch_pokeapi.py` genera `data/species.json`, `moves.json`, `types.json`, `natures.json`, `berries.json` y `growth.json`. Cachea las respuestas en `tools/.cache/pokeapi`. Los learnsets usan el primer version group disponible entre: scarlet-violet, sword-shield, ultra-sun-ultra-moon, sun-moon y x-y.

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
