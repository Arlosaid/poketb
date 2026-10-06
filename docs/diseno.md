# Diseño del juego (MVP)

## Fantasía
Mis Pokémon viven sobre mi barra de tareas. Mientras trabajo, una parte de mi equipo explora una ruta y pelea sola en un panel pequeño a la derecha. Los demás descansan en "casa" (a la izquierda): pasean, se sientan, se duermen y me miran cuando acerco el cursor. Mi compañero siempre está visible. Los cuido con caricias y bayas. Nunca hay castigos crueles.

## Pantalla
```
┌──────────────────────────── ventana transparente (ancho de pantalla) ───────────────────────────┐
│   (espacio para burbujas, números de daño, saltos; todo pasa clics excepto sprites y UI)        │
│  🐾 casa: mascotas paseando sobre el borde de la barra         ╭── panel de pelea ─────────╮   │
│  ───────────────────────────────────────────────────────────   │ cielo + parallax + equipo │   │
╞══════════════════════════════════ barra de tareas ════════════╧═══════════════════════════╧═══╡
```

## Modos
- **Modo pelea:** el panel de pelea está activo y el equipo (1–6) recorre la ruta.
- **Modo descanso:** el panel se pliega y el equipo descansa para recuperarse. En casa se ven las mascotas elegidas.
- **Pausa:** el tiempo de juego se detiene; las mascotas siguen animadas pero sin necesidades.

## Bucle de pelea
1. El equipo camina hacia la derecha y el fondo hace parallax. La barra de progreso muestra el avance hacia el jefe.
2. Cada 6–12 s aparece un salvaje según la tabla de la ruta y la hora (día o noche).
3. Combate automático: el líder pelea, se alternan turnos según la velocidad y se usa un movimiento de daño aleatorio entre los que conoce (con peso por la efectividad).
4. Al ganar hay EXP para todos y a veces una baya. Si el salvaje está débil, a veces se lanza una Poké Ball.
5. Tras ~20 encuentros aparece el **jefe** (Pidgeotto). Al vencerlo sale "¡Ruta despejada! Próximamente: …" y la ruta se repite.
6. Si cae todo el equipo, vuelven a casa caminando y se recuperan con el tiempo. No se pierde nada.

## Mascotas
- Estados: pasear, quieto, sentarse, dormir, mirar al cursor, recibir caricias, comer, ser arrastrado y caer.
- **Acariciar** (clic): corazones y +amistad (con límite por hora para que no se pueda abusar).
- **Dar baya** (clic derecho → baya): un menú chiquito con las bayas que tengo. Reacciona según su naturaleza:
  - le gusta: Happy/Joyous, +amistad y el gusto queda "descubierto" en la PC;
  - no le gusta: retrato Sad, poca amistad.
- **Arrastrar y soltar:** cae con suavidad y rebota un poco.
- **Necesidades:**
  - Hambre: baja ~1 punto cada 6 min y más rápido peleando.
  - Energía: baja al pelear y sube en casa.
  - Con hambre o energía bajas solo se pone de mal humor (retrato Worried/Sad) y gana menos amistad.
- **Noche:** duermen más. Tras 5 min sin actividad en la PC, se acurrucan a dormir.

## Mascotas vivas (Fase 8)
- **Siempre visibles:** por delante de las demás ventanas, salvo con apps a pantalla completa. Desde la bandeja se pueden esconder 30 min o quitar "Siempre al frente".
- **Personalidad:** cada Pokémon tiene su característica canon ("Le encanta comer", "Huye rápido"…) y de ahí un rasgo: Glotón, Dormilón, Travieso, Tranquilo, Orgulloso, Enérgico, Gruñón, Juguetón, Curioso, Soñador, Tiquismiquis, Payaso o Tímido. El rasgo cambia cuánto pasean, duermen, bailan, se lucen, juegan o miran el cielo. También tienen un lugar favorito en la casa, y los nocturnos duermen de día.
- **Necesidades:** saciedad, energía, **diversión** y amistad, visibles en la ficha.
- **Interacciones:**
  - **Clic:** caricia.
  - **4 clics rápidos:** cosquillas.
  - **Frotar el mouse encima:** rascarle.
  - **Arrastrar y soltar:** lanzarlo. Da una voltereta, y los voladores planean.
  - **Dejar el mouse quieto encima:** ficha.
  - **Clic derecho:** baya, pelota, dormir/despertar o ficha.
  - **Pelota:** la lanzas (o la arrastras) y los juguetones la persiguen y la patean.
- **Entre ellos:** se saludan, se persiguen y duermen la siesta juntos. Cuanto más juegan juntos, más se buscan (lazos).
- **Vuelos:** de vez en cuando, los voladores dan un paseo por toda la pantalla y vuelven a casa.
- **Reaccionan a la PC:**
  - **Según la app:** con apps de trabajo están más tranquilos, con música bailan, con videos se sientan a mirar contigo y con juegos se emocionan.
  - **Al volver tras un rato:** te reciben.
  - **Pausas:** tras 50 min seguidos, te proponen una pausa; si la tomas, el equipo gana +10 % de EXP durante 30 min.
  - **Otros avisos:** de madrugada te dicen que ya es tarde, y te avisan si queda poca batería.
- **Cuidar sirve:** los mimos curan un poco a los heridos o debilitados, y un Pokémon contento gana +5 % de EXP.

## Amistad (0–255)
| Evento | Cambio |
|---|---|
| Caricia | +1 (máximo +10 por hora) |
| Baya que le gusta | +3 |
| Baya neutra | +2 |
| Baya que no le gusta | +1 |
| Ganar un combate | +1 cada 5 victorias |
| Debilitarse | −1 |
| Mal humor | las ganancias se reducen a la mitad |

Con ≥200 de amistad se activan los efectos de afecto Gen 6+: un 10% de aguantar con 1 PS ("¡X aguantó para no decepcionarte!") y críticos x2 más probables.

## Progresión del MVP
- Charmander (Nv. 5) es el inicial y evoluciona a Charmeleon en el Nv. 16.
- Ruta 1 "Pradera":
  - salvajes de nivel 2–8 que escalan con el progreso;
  - jefe Pidgeotto, Nv. 14.
- Los capturados van a la PC, desde donde se arma el equipo (hasta 6) y se elige al compañero.
- **Mascotas:** se elige quién pasea por la casa (hasta 6, del equipo o de las cajas; el compañero siempre está). Se hace desde la bandeja (submenú "Mascotas") o con el botón "Mascota" de la ficha en la PC. Los que pelean en ese momento están en el panel y vuelven a casa al terminar.

## Progresión (Fase 7)
Inspirada en Taskbar Hero, pero con piezas de Pokémon. Todo se paga con **monedas** que caen al ganar combates (también offline).
- **Monedas:** `base_experience × nivel × 0.1 / 5` por victoria (jefe ×5). Se ven arriba en la PC y como "+N" sobre el líder.
- **Árbol del entrenador** (pestaña Árbol): mejoras globales de todo el equipo en 4 ramas. Cada nodo tiene niveles, costo creciente y requisitos de otros nodos.
  - Combate: Fuerza (daño), Guardia (Def/DefEsp), Vigor (PS), Paso ligero (Vel), Ojo ágil (crítico).
  - Captura: Puntería (Poké Ball), Ojo clínico (lanzas antes), Red segura (más lanzamientos), Bola dorada (empujón final).
  - Economía: Botín (monedas), Estudio (EXP), Rastreo (más bayas y objetos).
  - Cuidado: Siesta (descansan más rápido), Merienda (más lento el hambre), Vínculo (más caricias por hora).
- **Entrenar** (pestaña Entrenar, por Pokémon):
  - **Vitaminas** (PS Plus, Proteína, Hierro, Calcio, Zinc, Carburante): hasta 10 dosis por stat, +4% del stat cada una.
  - **Movimientos:** se eligen a mano hasta 4 de los que ya aprendió; cada uno sube de **maestría** (0–5, +10% de potencia por nivel).
  - **Objetos:** 2 por Pokémon.
- **Mochila:** objetos equipables (Cinta Fuerte, Gafas Especiales, Casco Dentado, Chaleco Asalto, Garra Rápida, Restos, Periscopio, Huevo Suerte, Moneda Amuleto) con 4 niveles: Común, Poco común, Raro y Épico. **3 iguales del mismo nivel se fusionan en 1 del siguiente.** Caen con 12% de probabilidad al ganar; el jefe siempre suelta uno de nivel Poco común o mejor.
- Nada de esto se pierde ni se castiga: el árbol y los objetos son un camino de mejora sin vuelta atrás.

## La PC
Ventana nativa pequeña, con un marco estilo PC de Pokémon y tres pestañas:
- **Cajas:** retrato, nombre, nivel, naturaleza, corazones de amistad y gustos de sabor descubiertos.
- **Equipo:** 6 espacios (se arrastra desde las Cajas) y botón "Compañero".
- **Bayas:** el inventario.

Además muestra los créditos y las opciones.

Se abre con la **Poké Ball** que está en la casa (a la izquierda) o en el panel de pelea (abajo a la derecha), además de la burbuja de la mascota y la bandeja. La PC ahora tiene seis pestañas: **Pokémon** (equipo y cajas), **Entrenar**, **Mochila**, **Árbol**, **Bayas** y **Créditos**, con las monedas siempre visibles arriba.

## Bandeja
Menú: Abrir PC / Equipo · Modo pelea / Modo descanso · Pausar · Créditos · Salir. Con `--debug` aparece también un submenú Debug.

## Guardado
Archivo `user://save.json`. Se guarda cada 60 s y al salir. Al abrir se calcula el progreso offline (máximo 8 h) y aparece un resumen breve.

## Todos los Pokémon (Fase 9)
- **Las 1025 especies** están en los datos canon. Las 984 que tienen sprites en SpriteCollab aparecen en el mundo; las otras 41 aparecerán cuando la comunidad las dibuje (basta con volver a correr las herramientas).
- **Rutas:** después de la Ruta 1 vienen 11 rutas temáticas (Bosque Verde, Costa Celeste, Monte Roca, Prado Chispa, Pantano Sombrío, Volcán Ascuas, Cumbre Helada, Mar Abierto, Ruinas Psíquicas, Picos del Cielo y Calle Victoria) y el Santuario Legendario. Al vencer al jefe, el equipo pasa solo a la siguiente. Cada especie vive en una ruta según sus tipos y su nivel; los legendarios y singulares, en el Santuario.
- **Cada movimiento tiene su animación:** el cuerpo hace el gesto que corresponde (puñetazo, patada, mordisco, zarpazo, cabezazo, giro, rugido, aleteo…) y sale el efecto de su estilo con los colores de su tipo (llamarada, rayo, trueno, lluvia de rocas, terremoto, ola, viento, ondas psíquicas, drenaje, explosión, excavar, vuelo…).
- **En casa, cada tipo tiene lo suyo:** los de fuego sueltan brasas, los de agua hacen una fuente, los eléctricos echan chispas, los de planta hacen la fotosíntesis de día, los de tierra excavan y salen en otro lado, los psíquicos se teletransportan, los fantasmas se vuelven translúcidos y flotan, los bichos se cuelgan de un hilo de seda, los de roca ruedan, los de hielo hacen nevar y los de lucha practican golpes. Además entrenan sus movimientos y a veces hacen combates de práctica entre ellos (sin daño).
- **Vuelos por toda la pantalla:** pájaros, bichos alados, dragones y fantasmas cruzan la pantalla de lado a lado, dan rizos y se quedan flotando un momento antes de volver. Pueden volar dos a la vez.
- **Habilidad:** cada Pokémon tiene una de las habilidades normales de su especie (siempre la misma), que se ve en la ficha y en la PC.
