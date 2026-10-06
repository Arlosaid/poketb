class_name UiTheme
extends RefCounted
## Tema único de la UI: fuente pixel y marcos 9-patch propios (assets/ui).
## Se construye en código para que no haya un .tres con valores sueltos.

const FONT_PATH := "res://assets/fonts/ark-pixel-10px-proportional-latin.ttf"
const FONT_SIZE := 10

static var _theme: Theme
static var _font: FontFile


static func font() -> FontFile:
	if _font == null:
		_font = load(FONT_PATH)
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font.generate_mipmaps = false
		_font.force_autohinter = false
	return _font


## StyleBox 9-patch. `m` = margen de la textura; el último px abajo/derecha es sombra.
static func nine(path: String, m: int, content := -1, shadow := 1) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(path)
	sb.texture_margin_left = m
	sb.texture_margin_top = m
	sb.texture_margin_right = m + shadow
	sb.texture_margin_bottom = m + shadow
	var c := m + 1 if content < 0 else content
	sb.content_margin_left = c
	sb.content_margin_top = c - 1
	sb.content_margin_right = c + shadow
	sb.content_margin_bottom = c + shadow - 1
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = FONT_SIZE
	t.set_color("font_color", "Label", Palette.INK)
	t.set_constant("line_spacing", "Label", 1)
	var panel := nine("res://assets/ui/panel.png", 5)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var dialog := nine("res://assets/ui/dialog.png", 5, 7)
	t.set_type_variation("DialogPanel", "PanelContainer")
	t.set_stylebox("panel", "DialogPanel", dialog)
	t.set_type_variation("DialogLabel", "Label")
	t.set_color("font_color", "DialogLabel", Palette.PAPER)
	t.set_stylebox("normal", "Button", nine("res://assets/ui/button.png", 4, 4))
	t.set_stylebox("hover", "Button", nine("res://assets/ui/button_hover.png", 4, 4))
	t.set_stylebox("pressed", "Button", nine("res://assets/ui/button_pressed.png", 4, 4))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", nine("res://assets/ui/button.png", 4, 4))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, "Button", Palette.INK)
	t.set_color("font_disabled_color", "Button", Palette.OAK)
	t.set_type_variation("Slot", "PanelContainer")
	t.set_stylebox("panel", "Slot", nine("res://assets/ui/slot.png", 4, 3))
	_theme = t
	return t
