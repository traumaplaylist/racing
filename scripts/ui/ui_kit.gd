class_name UiKit
extends RefCounted
## Shared look for all screens: large, high-contrast, readable at 1280×720 and on phones later.

const BG := Color(0.09, 0.07, 0.06, 0.82)
const BG_SOLID := Color("1c1613")
const ACCENT := Color("1fc8c0")
const WARM := Color("ffb21f")
const TEXT := Color("fbf3e6")
const DIM := Color("bfae98")
const BAD := Color("ff5a3c")
const GOOD := Color("4fe07a")


static func box(color := BG, radius := 10, border := 0, border_color := ACCENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_color
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func panel(color := BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color))
	return p


static func label(text: String, size := 22, color := TEXT, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	if outline > 0:
		ls.outline_size = outline
		ls.outline_color = Color(0, 0, 0, 0.85)
	l.label_settings = ls
	return l


static func set_label_color(l: Label, c: Color) -> void:
	l.label_settings.font_color = c


static func button(text: String, size := 24, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", size)
	var base := Color("3a2c24") if not primary else Color("147f7a")
	b.add_theme_stylebox_override("normal", box(base, 8))
	b.add_theme_stylebox_override("hover", box(base.lightened(0.15), 8, 2, WARM))
	b.add_theme_stylebox_override("pressed", box(base.darkened(0.2), 8, 3, WARM))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 8, 4, WARM))
	b.add_theme_stylebox_override("disabled", box(Color("2a2420"), 8))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color("7d7064"))
	b.focus_entered.connect(func() -> void: Sfx.play("ui_move", 0.6))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	return b


## Toggle-style selection button (car / weapon pickers).
static func choice(text: String, size := 22) -> Button:
	var b := button(text, size)
	b.toggle_mode = true
	var on := box(Color("147f7a"), 8, 3, ACCENT)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", box(Color("1a9a94"), 8, 3, WARM))
	return b


## Simple bar made of two ColorRects; returns the container, fill is child 0 of child 0.
static func bar(width: float, height: float, fill_color: Color) -> Control:
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.6)
	back.custom_minimum_size = Vector2(width, height)
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.position = Vector2(2, 2)
	fill.size = Vector2(width - 4, height - 4)
	fill.name = "Fill"
	back.add_child(fill)
	return back


static func set_bar(b: Control, frac: float, color: Color = Color(0, 0, 0, 0)) -> void:
	var fill: ColorRect = b.get_node("Fill")
	fill.size.x = maxf(0.0, (b.custom_minimum_size.x - 4.0) * clampf(frac, 0.0, 1.0))
	if color.a > 0.0:
		fill.color = color
