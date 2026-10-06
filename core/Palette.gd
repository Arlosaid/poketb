class_name Palette
## Paleta cerrada de 32 colores (ver docs/arte.md). Nunca usar hex sueltos fuera de aquí.

const INK := Color("#2b1d1a")
const BARK := Color("#4a3128")
const WOOD := Color("#6e4a35")
const OAK := Color("#9a6b47")
const TAN := Color("#c99a65")
const SAND := Color("#e8c895")
const CREAM := Color("#f6e7c1")
const PAPER := Color("#fffaf0")
const PINE := Color("#1f3a33")
const FOREST := Color("#2f5a3d")
const LEAF := Color("#4b8049")
const GRASS := Color("#77ab55")
const SPROUT := Color("#a9d16a")
const LIME := Color("#d6ec9a")
const MIDNIGHT := Color("#1b2140")
const NIGHT := Color("#2c3a6b")
const DUSK := Color("#45609c")
const SKY := Color("#6b93cf")
const HAZE := Color("#9cc4ec")
const MIST := Color("#d2ebf7")
const PLUM := Color("#5a2238")
const BERRY := Color("#9c3b4a")
const EMBER := Color("#d8584f")
const FLAME := Color("#f08a5a")
const AMBER := Color("#f9b860")
const HONEY := Color("#ffe08a")
const LILAC := Color("#8a5a9c")
const ORCHID := Color("#c48ac8")
const BLUSH := Color("#f2a7b8")
const PETAL := Color("#ffd4dc")
const TEAL := Color("#3f8f8f")
const MINT := Color("#8fd3c7")

const ALL: Array[Color] = [
	INK, BARK, WOOD, OAK, TAN, SAND, CREAM, PAPER,
	PINE, FOREST, LEAF, GRASS, SPROUT, LIME,
	MIDNIGHT, NIGHT, DUSK, SKY, HAZE, MIST,
	PLUM, BERRY, EMBER, FLAME, AMBER, HONEY,
	LILAC, ORCHID, BLUSH, PETAL, TEAL, MINT,
]

## Nombres en el mismo orden que ALL (iguales a docs/arte.md y a los JSON de datos).
const NAMES: PackedStringArray = [
	"ink", "bark", "wood", "oak", "tan", "sand", "cream", "paper",
	"pine", "forest", "leaf", "grass", "sprout", "lime",
	"midnight", "night", "dusk", "sky", "haze", "mist",
	"plum", "berry", "ember", "flame", "amber", "honey",
	"lilac", "orchid", "blush", "petal", "teal", "mint",
]


## Color por nombre ("cream", "dusk"...). Falla si no es de la paleta.
static func by_name(color_name: String) -> Color:
	var i := NAMES.find(color_name)
	assert(i >= 0, "color fuera de la paleta: " + color_name)
	return ALL[maxi(i, 0)]


## Color de la paleta con alfa (la transparencia sí está permitida).
static func a(c: Color, alpha: float) -> Color:
	return Color(c, alpha)


## Color de barra de PS según la fracción restante.
static func hp_color(frac: float) -> Color:
	if frac > 0.5:
		return MINT
	if frac > 0.2:
		return AMBER
	return EMBER
