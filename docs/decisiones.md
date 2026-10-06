# Registro de decisiones

Formato: fecha · decisión · por qué. Las más recientes van abajo.

## 2026-10-06 — Fundacionales

- **Motor:** Godot 4.7.2-stable con GDScript. El ejecutable está en `Desktop\Godot_v4.7.2-stable_win64.exe`.
- **Renderer `gl_compatibility`.** Gasta menos energía que Forward+ y es el más probado con ventanas transparentes en Windows.
- **Clic a través con una GDExtension propia (`native/`, singleton `DesktopNative`).** En `display_server_windows.cpp` (4.7) verifiqué dos cosas:
  - `window_set_mouse_passthrough(polygon)` usa `SetWindowRgn`, que además de dejar pasar los clics **deja de dibujar** lo que queda fuera del polígono. Eso borraría el fondo de la franja y los efectos.
  - `WINDOW_FLAG_MOUSE_PASSTHROUGH` responde `HTTRANSPARENT`, que solo pasa los clics a ventanas del mismo hilo.

  La extensión activa y desactiva `WS_EX_LAYERED|WS_EX_TRANSPARENT`. Cada frame, GDScript compara la posición global del cursor con los rectángulos clicables. La alternativa era una DLL MIT de terceros (Godot-WinMousePassthrough); el usuario eligió compilar la nuestra.
- **Sin ícono en la barra de tareas:** `WS_EX_TOOLWINDOW` + `ITaskbarList::DeleteTab`. Se reaplica periódicamente porque Godot recalcula el estilo de la ventana.
- **Inactividad:** se mide con `GetLastInputInfo` (teclado y mouse de todo el sistema), no solo con el mouse.
- **Apps a pantalla completa:** si hay un juego, video o presentación en pantalla completa (`SHQueryUserNotificationState`), la franja se oculta y el juego baja a 5 FPS. Así no estorba.
- **Ventana `no_focus`:** hacer clic en un Pokémon no le roba el foco a la app donde escribo. La depuración va por el menú de la bandeja, no por el teclado.
- **Layout (elegido por el usuario):** la casa de las mascotas va a la izquierda, sobre la barra de tareas, y el panel de pelea enmarcado a la derecha, junto a la bandeja, con un ~40% del ancho por defecto. El compañero pasea por todo el ancho.
- **Escala entera** según la altura de la pantalla: ≤1080 → x2, ≤1600 → x3, más → x4.
- **Sprites:** se bajan con *sparse checkout* de SpriteCollab (el repo pesa ~2 GB) mediante `tools/fetch_sprites.py`, y solo la forma base de cada especie. La copia está en `assets/raw/spritecollab/`.
- **Créditos:** `credits.txt` puede citar a un autor por su ID de Discord, que se traduce a nombre con `credit_names.txt`. Si un ID no tiene nombre público, se acredita tal cual.
- **Fondos procedurales propios.** Los packs CC0 de parallax que encontré (ansimuz "Forest background", macrune12 "Parallax Forest", val-demar "Dark Forest") son bosques oscuros cuya paleta no combina con PMD. Los genero cuantizados a nuestra paleta.
- **Especies:** Charmander como inicial. En la Ruta 1, de día: Pidgey, Rattata, Caterpie y Oddish; de noche: Hoothoot y Spinarak. Jefe: Pidgeotto. También se bajan las evoluciones para que los capturados puedan evolucionar.
- **Combate simplificado:** fórmula de daño Gen 5+, solo movimientos de daño en el MVP (sin estados), orden por velocidad y crítico 1/24 x1.5. EXP con la fórmula Gen 6+ y reparto a todo el equipo.
- **Captura:** Poké Balls ilimitadas en el MVP. Se intenta a veces (cuando el salvaje tiene <50% de PS) con la fórmula Gen 5+.
- **Offline:** simulación estadística con tope de 8 h. Da EXP, bayas y amistad, pero no captura.
- **Convenciones de código:** identificadores en inglés (estilo GDScript oficial) y comentarios, documentación y textos del juego en español.

## 2026-10-06 — Fase 1

- **Validación visual sin capturar el escritorio.** Una captura de pantalla real incluye las ventanas privadas que estén abiertas detrás de la franja. Por eso las capturas son del viewport (`Game.shot`) compuestas sobre un fondo neutro (`tools/compose_shot.py`). Se eliminó `tools/screenshot.ps1`.
- **El clic a través quedó validado** con `WindowFromPoint`:
  - sobre una zona vacía, el clic va a la app de abajo;
  - con el cursor sobre el Pokémon, va al juego, y el clic llega como evento;
  - al alejar el cursor, vuelve a pasar.

  La transparencia por píxel sigue funcionando con `WS_EX_LAYERED`.
- **Suelo:** está 2 px por encima del borde de la ventana para que la sombra no se corte.
- **Consumo inicial:** ~5% de un núcleo y ~160 MB con un Pokémon a 10 FPS. Se revisa en la Fase 6.
- **godot-cpp** se fija en la rama 4.5, porque no hay rama 4.7 y la API de GDExtension es compatible hacia adelante.
