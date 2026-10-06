# Modo mascota: guía para seguir mejorándolo

Documento de traspaso: cómo está hecho el modo mascota (Fase 8), dónde se ajusta cada cosa, cómo probarlo y qué queda pendiente. Si cambias algo, actualízalo aquí, en `docs/decisiones.md` y en `docs/tecnico.md`.

## Qué pidió el usuario (norte)
- Que sea dinámico y personalizable, y que de verdad se le tome cariño a los Pokémon: que sean únicos y tengan muchas animaciones.
- Que esté siempre por delante de todo, con mucha interacción.
- Que cuidarlos sirva de algo (descanso si están débiles, cambiar de humor) y que reaccionen a la PC.
- Las prioridades que dio son, en orden: **seguridad** (no estorbar y privacidad), **rendimiento**, y luego lo demás. También pidió que los cuadros sean **pequeños** y que la mascota **no tenga el botón de PC**.

## Reglas que no se rompen
1. **Nunca estorbar.** Solo es clicable lo que está registrado en `Passthrough`. Los globitos, los textos y la ficha no son clicables. La ventana de vuelo siempre deja pasar el mouse. Todo se esconde con apps a pantalla completa y con "Esconder mascotas".
2. **Privacidad.** De la PC solo se lee el nombre del `.exe` activo (`DesktopNative.get_foreground_app`). Nunca se leen títulos, teclas ni contenido. No se guarda ni se escribe en el log, y se apaga desde la bandeja.
3. **Consumo.**
   - Lo periódico va en timers: `PcSense` cada 3 s y la batería cada 60 s.
   - La ventana de vuelo está oculta si nadie vuela.
   - Con 5 min de inactividad, o con las mascotas escondidas, se baja a 5 FPS.
   - Pedir FPS altos solo mientras pasa algo: `desk.keep_awake()` para acción y `keep_ambient()` para paseos.
4. **Sin castigos.** Las necesidades bajas solo se expresan con globitos o reduciendo a la mitad lo que se gana de amistad. Lo bueno da bonus: curar, +EXP.
5. **Canon y datos.** Los números canon salen de PokeAPI (`tools/fetch_pokeapi.py`). Los pesos de comportamiento, apps y tiempos viven en JSON.
6. **Arte.** Paleta cerrada (`tools/gen_ui.py` lo verifica), escala entera, nada de rotar ni escalar pixel art. Por eso la pelota "rueda" espejándose.

## Mapa de archivos
| Archivo | Qué hace |
|---|---|
| `pet/PetBrain.gd` | Máquina de estados de cada mascota, interacciones y reacciones. Es el corazón. |
| `pet/HomeArea.gd` | La casa: coordina la pelota, los juegos entre mascotas, los vuelos y las reacciones a la PC. Elige quién habla (`_speaker`). |
| `pet/Personality.gd` | Característica canon → rasgo → pesos (con caché). Indica si es nocturno o si puede volar. |
| `pet/PcSense.gd` | Sentidos sobre la PC: app activa, regreso del usuario, racha de uso y pausas, madrugada, batería. |
| `pet/ToyBall.gd` | Pelota con física simple. Se arrastra y se lanza; emite `thrown`. |
| `pet/FlightWindow.gd` | Ventanita transparente (64x64 lógicos) que lleva al volador por waypoints en coordenadas de pantalla. |
| `ui/Emote.gd` | Globito de 11x13 con un ícono de 7x7. No clicable. |
| `ui/Bubble.gd` | `Bubble.say(hud, actor, texto)`: una línea, no clicable. |
| `ui/ActionBar.gd` | Barrita del clic derecho (íconos de 9x9 en botones "Chip"). |
| `ui/BerryMenu.gd` | Menú compacto de bayas (solo íconos; la info aparece al pasar el mouse). |
| `ui/PetCard.gd` | Ficha: nombre, nivel, rasgo, característica y 4 barritas. |
| `core/Roster.gd` | Necesidades (`tick`), `pet`, `play`, `cuddle_heal`, `bonds`, `start_cheer` y `cheer_exp_pct`. Quiénes pasean: `pets`, `pet_uids()`, `toggle_pet()` y `PETS_MAX`. |
| `pokemon/PokemonInstance.gd` | Campos `fun`, `pid` y `fav_x`; `characteristic_key()`, `is_cheerful()`. |
| `core/Game.gd` | `settings` (topmost, flights, app_react, wellbeing), `hide_pets()` y `pets_hidden()`. |
| `core/Tray.gd` | Opciones de la bandeja, incluido el submenú "Mascotas" (`_sync_pets`). |
| `core/DesktopWindow.gd` | Siempre al frente (`_apply_topmost` y `reassert_topmost` cada 2 s) y FPS. |
| `native/src/desktop_native.cpp` | `get_foreground_app()` y `get_power_status()`. |
| `data/personality.json` | Característica → rasgo, pesos por rasgo, especies nocturnas y voladoras. |
| `data/apps.json` | `.exe` → categoría, reacción por categoría y tiempos de bienestar. |
| `data/characteristics.json` | Textos canon de las 30 características (los genera `fetch_pokeapi.py`). |
| `tools/gen_ui.py` → `pet_ui()` | Arte: globitos, íconos, chip, globo de texto y pelota. |
| `tools/pack_sprites.py` | `WANTED` y `ALTERNATIVES`: animaciones lógicas y sus alternativas. |
| `pet/TypeAct.gd` | Acciones propias de cada tipo (brasas, fuente, chispas, excavar, teletransporte, atravesar, hilo de seda…). |
| `data/pet_types.json` | Qué acciones tiene cada tipo, con su animación, partículas, duración y peso. |
| `battle/MoveFx.gd` | Animación de los movimientos (también se usa en casa para entrenar). |

## Cómo funciona

### Estados (`PetBrain.State`)
`IDLE, WANDER, SIT, LAY, SLEEP, WAKE, LOOK, PETTED, EAT, DRAG, FALL, ACT, CHASE, SOCIAL, FOLLOW, AWAY`
- `ACT`: animación de una vez (`_act(anim)`); al terminar vuelve a IDLE o LOOK.
- `AWAY`: está volando (el actor se oculta y lo lleva `FlightWindow`).
- `FOLLOW`: camina hacia la x del cursor (te persigue, te recibe o te propone una pausa).
- `_choose_next()` sortea entre: wander, idle, sit, lay, sleep, stretch, dance, show, sky, social, ball y fly. Cada peso multiplica:
  - el rasgo (`_wv(key)`);
  - la hora: `sleepy_time = es de noche XOR es nocturno`;
  - el cansancio, el aburrimiento y la salud (débil: descansa más; debilitado: solo lay o sleep);
  - la app activa: `home.calm`, `home.watching`, `home.music`.
- Mientras hay un menú abierto (`_menu`), la mascota espera.

### Quién pasea
- `Main._sync_home` muestra `Roster.pet_uids()`. **Las mascotas no pelean** (`Roster.can_fight` las excluye), así que se quedan siempre en casa: nadie entra ni sale solo. El compañero es una mascota más (puede serlo o no).
- Los capturados nuevos **no** se vuelven mascotas solos (salvo en los escenarios de prueba: `Roster.auto_pet`).
- **Tres listas sin cruces:** equipo (`Roster.team`, pelean), mascotas (`Roster.pets`, viven en casa) y cajas (`box_members()`, el resto). `set_team`, `set_pets` y `toggle_pet` mantienen que nadie esté en dos a la vez.
- El jugador elige en la pestaña **Mascotas** de la PC (6 casillas + cajas, con arrastrar y soltar y botones "Al equipo" / "A mascotas" / "A la caja" en la ficha) o desde la bandeja (submenú "Mascotas"). Hay un máximo de 6. Si eliges a uno que va caminando por la ruta, sale del panel al momento; si está en medio de un combate, sale al terminar.
- Para revisar un guardado real sin tocarlo: copiar `save.json` a `scenario_save.json` (en `%APPDATA%/Godot/app_userdata/Taskbar Pokémon/`) y correr `--scenario=save_load_pets` (imprime quién está en casa y saca `pets_*`).

### Interacciones
| Gesto | Efecto |
|---|---|
| Clic | `pet()`: corazones y amistad (límite por hora), `cuddle_heal` si está herido y un globito si tiene una necesidad. Si dormía, despierta. |
| 4 clics en 1.3 s | `tickle()`: animación Laugh, `Roster.play(+8 de diversión)`. |
| Frotar encima (5 cambios de dirección en 1.6 s) | `rub()`: animación Stretch, `play(+5)` y cura un poco. |
| Mouse quieto 1.2 s encima | `PetCard`. |
| Arrastrar y soltar | Lanza con la velocidad del cursor. Si el golpe es fuerte, Tumble y globito de estrella; los voladores planean. |
| Clic derecho | `ActionBar`: baya, pelota, dormir/despertar, ficha. |
| Pelota | La lanzas (o un clic la tira hacia arriba) y salen detrás los juguetones según `_wv("ball")`. Cada uno se acerca con un desfase y patea el más cercano. |

### Vida social (`HomeArea.start_social`)
- El compañero se elige según el lazo (`Roster.bond`) y la cercanía (`SOCIAL_RANGE`).
- Hay tres tipos:
  - `greet`: van el uno hacia el otro, Nod y corazones;
  - `chase`: uno huye y el otro lo alcanza (Joy y Laugh);
  - `nap`: se duerme al lado de uno que ya duerme.
- Al terminar bien: `add_bond +1` y +5 de diversión a los dos.

### Acciones por tipo (Fase 9)
- `_choose_next` tiene dos opciones más: `type` (`start_type_act`) y `train`. Sus pesos base están en `data/pet_types.json` (`base_weight`, `train_weight`) y los rasgos los multiplican (`type` y `train` en `personality.json`).
- `TypeAct.pick(tipos, noche)` sortea entre las acciones de sus tipos (algunas solo de día o de noche). Clases (`kind`):
  - `particles`/`glow`: anima y suelta partículas con un patrón (`rise`, `fall`, `orbit`, `fountain`, `zap`, `puff`, `sparkle`);
  - `teleport` (psíquico, fantasma, siniestro): se desvanece y aparece en otro lado;
  - `dig` (tierra): se hunde, un rastro de polvo avanza bajo tierra y sale en otro lado;
  - `phase` (fantasma; siniestro de noche): se vuelve translúcido y flota a la deriva;
  - `hover` (volador, psíquico): se eleva y se mece;
  - `roll` (roca, acero): rueda por el suelo;
  - `web` (bicho): se cuelga de un hilo de seda desde arriba y se balancea.
- Si la mascota cambia de estado a mitad (la arrastras, la acaricias), `TypeAct` se cancela y deja al actor como estaba.

### Entrenar y combates de práctica (Fase 9)
- `train()`: practica uno de sus movimientos con la misma animación de la pelea, pero en chico (`MoveFx` con `small`), y a veces dice el nombre del movimiento.
- Vida social `spar` (probabilidad `spar_chance` × rasgo): se ponen a unos pasos y se turnan 4 veces. No hay daño: el otro hace "Hurt" de juego y al final los dos asienten con corazones (+1 de lazo y +6 de diversión).

### Vuelos
- Vuelan los de tipo volador, los de forma con alas (`wings`, `bug-wings`), los de la habilidad Levitación, los fantasmas sin patas y la lista `fly` de `personality.json`; nunca los de `no_fly`. Son ~190 especies.
- Estilo (`Personality.flight_style`): `bird`, `bug` (aleteo nervioso), `dragon` (rápido, con rizos) y `float` (fantasmas y levitadores: lento y translúcido). Se puede forzar por especie con `flight_style`.
- Condiciones en `can_start_flight`:
  - opción activa, sin pantalla completa y con el usuario activo hace <60 s;
  - pausas y vuelos simultáneos en `personality.json → flight` (por defecto, 45–120 s entre vuelos, 3–6 min por Pokémon y hasta 2 a la vez);
  - energía y PS suficientes, y la hora correcta (nocturnos: la lista `nocturnal` más los tipos fantasma y siniestro).
- La ruta (`start_flight`) cruza **toda la pantalla** en zigzag, de un borde al otro y a alturas al azar (3–5 tramos); a veces da un rizo o se queda flotando unos segundos, y aterriza en una x al azar de la casa. Luego `land_from_flight` baja planeando.
- Cada vuelo usa una `FlightWindow` del grupo (se reusan); su tamaño se ajusta al Pokémon (mínimo 64x64 lógicos).
- Para probarla: `home.force_flight(brain)`.

### Reacciones a la PC (`PcSense` → `HomeArea`)
- **`app_changed(cat)`:** ajusta `calm`, `watching` y `music`, y algunos reaccionan (con video se sientan de espaldas "mirando la pantalla").
- **`user_returned`:** el compañero va hacia ti y los demás muestran un "!".
- **`break_suggested` → `break_taken`:**
  - tras `work_minutes`, el compañero propone una pausa;
  - si descansas `break_minutes`, se activa `start_cheer` (+EXP durante un rato).
- **`late_night`:** una vez por noche.
- **`battery_low` y `battery_charging`:** solo en portátiles.

### Bonus de cuidarlos
- `Progression.exp_mult` suma `Roster.cheer_exp_pct(p)`: el ánimo del equipo, más un 5 % si `is_cheerful()`.
- `cuddle_heal`: un 8 % de los PS y +3 de energía, con 12 s de espera.

## Dónde ajustar (sin tocar lógica)
- Pesos por rasgo y especies nocturnas o voladoras: `data/personality.json`.
- Apps, reacciones y tiempos de pausa, madrugada y batería: `data/apps.json`.
- Constantes de gestos: arriba de `PetBrain.gd` (`TICKLE_CLICKS`, `RUB_REVERSALS`, `CARD_DWELL`, `THROW_MAX`…).
- Vuelos: `HomeArea.FLIGHT_GAP*`, `FlightWindow.SPEED` y `LOGICAL`.
- Necesidades: constantes de `Roster` (`FUN_DECAY_HOME`, `CUDDLE_*`, `CHEERFUL_EXP_PCT`).

## Agregar cosas (recetas)
- **Un rasgo nuevo:** agrégalo en `traits` y apúntalo desde `by_characteristic` (`data/personality.json`).
- **Un comportamiento autónomo nuevo:**
  1. Agrega la clave al diccionario de `_choose_next` y su `match`.
  2. Agrega el peso por defecto en `defaults`.
  3. Si usa una animación nueva, agrégala a `WANTED` y `ALTERNATIVES` en `tools/pack_sprites.py` y vuelve a empacar.
- **Una acción de tipo:** agrégala en `data/pet_types.json` (con un `kind` existente no hay que tocar código).
- **Una animación lógica:** la agregas a `ALTERNATIVES` con una lista de candidatas (la última debe existir siempre: Idle o Hop). Para regenerar: `python -I tools/pack_sprites.py` y `godot_console --headless --path . --import`. Muchas especies solo tienen 13 animaciones, así que siempre hay que dar alternativas. Usa `actor.has_real(name)` si una conducta depende de la animación real.
- **Un ícono de globito:** agrégalo a `EMOTE_ICONS` en `tools/gen_ui.py` (7x7, paleta) y corre `python -I tools/gen_ui.py`. El índice sale de `emotes_index.json`.
- **Una acción del clic derecho:**
  1. Dibuja un ícono de 9x9 en `action_icons()` (`gen_ui.py`).
  2. Agrega su índice en `ActionBar.ICON_INDEX`.
  3. Agrega la entrada en `PetBrain.open_actions()` y el caso en `_on_action()`.
- **Una categoría de app:** agrégala en `data/apps.json` (`categories` + `reactions`).
- **Un ajuste del jugador:** agrégalo en `Game.settings` (se guarda solo) y en `Tray` (ID, check y `_sync`).
- **Una función nativa:** `native/src/desktop_native.{h,cpp}` + `_bind_methods`.
  - Compila las dos variantes (debug y release) con el entorno de MSVC.
  - La DLL debug queda bloqueada si el juego está abierto: hay que pedir que lo cierren.
  - En GDScript, protege la llamada con `has_method` por si la DLL es vieja.

## Cómo probar
- `"<godot_console>" --path . -- --scenario=types --autoquit=120`: acciones por tipo, entrenar, combate de práctica y los cuatro estilos de vuelo (`p9_*`).
- `"<godot_console>" --path . -- --scenario=pet --autoquit=150`
  - Genera `shots/p3_home`, `p3_sleep` y `p8_*`: caricia, acciones, bayas, ficha, comer, cosquillas, rascar, mimos que curan, emociones, pelota, saludo, voltereta, pausa, ánimo, video y vuelo (la ventanita del vuelo se captura aparte en `p8_flight.png`).
  - Imprime el rasgo de cada mascota y el ánimo.
- Componer y mirar: `python -I tools/compose_shot.py shots/p8_x.png --x0 0 --x1 400 --zoom 3`. **Nunca** capturar el escritorio real.
- En escenarios `PcSense` no sondea: se dispara a mano, por ejemplo `main.home.sense.app_changed.emit("video")`.
- Clic a través y siempre al frente: abre `--scenario=still` y luego usa `tools/probe.ps1`:
  - `-Action find`: el exstyle debe tener 0x8 (TOPMOST);
  - `-Action move` + `-Action hit`: en una zona vacía debe responder la app de abajo y sobre el sprite, Godot.
- Regresión: correr también `battle`, `growth`, `save_write`, `save_load` y `showcase` y confirmar que no hay `ERROR` en los logs.

## Limitaciones conocidas
- No se detectan videos en el navegador (habría que leer el título, y eso está prohibido por privacidad).
- La batería solo funciona en portátiles.
- No se pudieron probar en vivo durante el desarrollo: el recorrido completo de un vuelo por la pantalla real, la reacción a apps reales y el recordatorio de pausa de 50 min. Hay que validarlos con el uso y ajustarlos.
- La ficha mide ~130 px lógicos de ancho con nombres largos. Se podría acortar.
- `_mood` y las reacciones eligen al azar: a veces no reacciona nadie (es intencional, para que no canse).

## Ideas pendientes (priorizadas)
1. **Posarse sobre ventanas** (estilo Shimeji): sentarse en la barra de título de la ventana activa y caerse con Tumble si la mueves. Hace falta una función nativa para el rect de la ventana activa (`GetWindowRect` del foreground y solo eso, sin títulos) y que el actor viva en una ventanita propia, como el vuelo.
2. **Shiny:** bajar las variantes de SpriteCollab (`sprite/XXXX/0000/0001`), importarlas y decidir la tasa (canon 1/4096; preguntar al usuario).
3. **Personalización:**
   - motes desde la PC o la ficha;
   - muebles para la casa (cojín, cama, macetero de bayas que crece) comprados con monedas y colocados arrastrándolos;
   - accesorios con los puntos de cabeza de `-Offsets.png` (riesgoso por el arte).
4. **Más juegos:** traer la pelota hasta el cursor, esconderse y buscar, entrenar entre ellos (Strike/Attack de broma), cepillarlo con una herramienta.
5. **Recuerdos y diario:** que la ficha muestre "le gusta: …", el día que lo atrapaste, cuántas veces jugaron juntos o su mejor amigo.
6. **Modo enfoque (Pomodoro)** explícito desde la bandeja: el compañero duerme a tu lado y al terminar te festeja.
7. **Sonidos suaves**, opcionales y apagados por defecto.
8. **Clima y estaciones:** que el comportamiento cambie según la estación (por ejemplo, más sueño en invierno).
