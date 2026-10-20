# ui_factory.gd
# -----------------------------------------------------------------------------
# Helper functions that create UI nodes (rectangles, texts, buttons, lights)
# from code, plus the color palette. The prototype needs no hand-made scenes.
#
# Positions use ANCHORS as fractions of the parent, measured like this:
#   x_min, y_min = bottom-left corner,  x_max, y_max = top-right corner
#   (0,0,1,1) = fill the whole parent;  (0,0.5,1,1) = top half.
# (Godot itself counts y from the top; rect() converts for us.)
# -----------------------------------------------------------------------------
extends RefCounted

const PuzzleRules = preload("res://scripts/puzzle_rules.gd")

# ---- Palette (placeholder "vault" theme) ----
const BACKGROUND := Color(0.055, 0.071, 0.090)
const PANEL := Color(0.106, 0.137, 0.172)
const PANEL_LIGHT := Color(0.165, 0.208, 0.255)
const SOCKET := Color(0.30, 0.33, 0.37)
const TEXT := Color(0.90, 0.93, 0.95)
const MUTED := Color(0.55, 0.60, 0.65)
const AMBER := Color(0.95, 0.66, 0.23)
const GOOD := Color(0.24, 0.86, 0.52)
const BAD := Color(1.00, 0.30, 0.30)
const LED_OFF := Color(0.22, 0.24, 0.27)
const KEY_FACE := Color(0.86, 0.83, 0.75)
const DARK := Color(0.08, 0.08, 0.09)
const CLEAR := Color(0, 0, 0, 0)
const PANEL_DARK := Color(0.072, 0.090, 0.114)
const LINE := Color(1, 1, 1, 0.08) # thin borders
const AMBER_DIM := Color(0.95, 0.66, 0.23, 0.30)

static var _bold: Font
static var _spaced := {} # letter-spaced fonts, by spacing


static func wire_color(c: int) -> Color:
	match c:
		PuzzleRules.WireColor.RED:
			return Color(0.88, 0.20, 0.20)
		PuzzleRules.WireColor.BLUE:
			return Color(0.20, 0.45, 0.95)
		PuzzleRules.WireColor.YELLOW:
			return Color(0.98, 0.84, 0.18)
		PuzzleRules.WireColor.WHITE:
			return Color(0.95, 0.95, 0.95)
		_:
			return Color(0.20, 0.78, 0.35) # GREEN


static func button_color(c: int) -> Color:
	match c:
		PuzzleRules.ButtonColor.RED:
			return Color(0.85, 0.18, 0.18)
		PuzzleRules.ButtonColor.BLUE:
			return Color(0.18, 0.42, 0.92)
		PuzzleRules.ButtonColor.YELLOW:
			return Color(0.98, 0.82, 0.15)
		_:
			return Color(0.94, 0.94, 0.94) # WHITE


static func light_color(c: int) -> Color:
	match c:
		PuzzleRules.LightColor.WHITE:
			return Color(1, 1, 1)
		PuzzleRules.LightColor.BLUE:
			return Color(0.25, 0.55, 1.0)
		PuzzleRules.LightColor.YELLOW:
			return Color(1.0, 0.88, 0.2)
		_:
			return Color(1.0, 0.22, 0.22) # RED


# ---- Fonts ----
# Godot's built-in default font (it has every symbol the keypad uses).
static func regular_font() -> Font:
	return ThemeDB.fallback_font


## Bold = the same font, drawn thicker.
static func bold_font() -> Font:
	if _bold == null:
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = 0.8
		_bold = fv
	return _bold


## Bold font with extra space between letters (for captions like "MISSION 01").
static func spaced_font(spacing: int) -> Font:
	if not _spaced.has(spacing):
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = 0.7
		fv.spacing_glyph = spacing
		_spaced[spacing] = fv
	return _spaced[spacing]


# ---- Layout ----
## Places a control inside its parent using bottom-left based fractions.
static func place(parent: Node, c: Control, x_min: float, y_min: float, x_max: float, y_max: float) -> Control:
	c.set_anchor(SIDE_LEFT, x_min, true)
	c.set_anchor(SIDE_RIGHT, x_max, true)
	c.set_anchor(SIDE_TOP, 1.0 - y_max, true)
	c.set_anchor(SIDE_BOTTOM, 1.0 - y_min, true)
	c.offset_left = 0
	c.offset_right = 0
	c.offset_top = 0
	c.offset_bottom = 0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	parent.add_child(c)
	return c


## An empty container (does not block touches).
static func area(parent: Node, name: String, x_min: float, y_min: float, x_max: float, y_max: float) -> Control:
	var c := Control.new()
	c.name = name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return place(parent, c, x_min, y_min, x_max, y_max)


## A colored rectangle (does not block touches unless block_touches = true).
static func rect(parent: Node, name: String, color: Color, x_min: float, y_min: float, x_max: float, y_max: float, block_touches := false) -> ColorRect:
	var r := ColorRect.new()
	r.name = name
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_STOP if block_touches else Control.MOUSE_FILTER_IGNORE
	place(parent, r, x_min, y_min, x_max, y_max)
	return r


static func text(parent: Node, name: String, value: String, size: int, color: Color, align: int, x_min: float, y_min: float, x_max: float, y_max: float, bold := false) -> Label:
	var l := Label.new()
	l.name = name
	l.text = value
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", bold_font() if bold else regular_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	place(parent, l, x_min, y_min, x_max, y_max)
	return l


## Same as text(), but letter-spaced capitals (small labels and captions).
static func caps(parent: Node, name: String, value: String, size: int, color: Color, align: int, x_min: float, y_min: float, x_max: float, y_max: float, spacing := 4) -> Label:
	var l := text(parent, name, value.to_upper(), size, color, align, x_min, y_min, x_max, y_max)
	l.add_theme_font_override("font", spaced_font(spacing))
	return l


static func flat_style(color: Color, radius := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 24 # smoother circles
	sb.anti_aliasing = true
	return sb


## A rounded panel (card, box) with an optional border. Does not block touches.
## Its StyleBoxFlat is panel.get_meta("style").
static func panel(parent: Node, name: String, color: Color, x_min: float, y_min: float, x_max: float, y_max: float, radius := 18, border_color := CLEAR, border_width := 0) -> Panel:
	var p := Panel.new()
	p.name = name
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := flat_style(color, radius)
	if border_width > 0:
		sb.set_border_width_all(border_width)
		sb.border_color = border_color
	p.add_theme_stylebox_override("panel", sb)
	p.set_meta("style", sb)
	place(parent, p, x_min, y_min, x_max, y_max)
	return p


## Button look: a rounded block with a darker "edge" at the bottom.
## When pressed the face drops down onto that edge (feels like a real key).
static func _key_style(bg: Color, radius: int, pressed: bool) -> StyleBoxFlat:
	var sb := flat_style(bg.darkened(0.12) if pressed else bg, radius)
	if pressed:
		sb.border_width_top = 10
		sb.border_color = CLEAR
	else:
		sb.border_width_bottom = 10
		sb.border_color = bg.darkened(0.42)
	return sb


## A tappable button. Returns the Button; its background StyleBox is in
## button.get_meta("style") so the color can be changed later.
static func button(parent: Node, name: String, label: String, size: int, bg: Color, fg: Color, x_min: float, y_min: float, x_max: float, y_max: float, on_pressed: Callable = Callable(), radius := 22) -> Button:
	var b := Button.new()
	b.name = name
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = false
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", bold_font())
	b.add_theme_font_size_override("font_size", size)
	restyle_button(b, bg, fg, radius)
	place(parent, b, x_min, y_min, x_max, y_max)
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


## Gives a button new colors (used for ON/OFF switches and selected options).
static func restyle_button(b: Button, bg: Color, fg: Color, radius := 22) -> void:
	var normal := _key_style(bg, radius, false)
	var pressed := _key_style(bg, radius, true)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", _key_style(bg.darkened(0.45), radius, false))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, fg)
	b.set_meta("style", normal)


## An invisible button: a big touch area (used for the wires).
static func touch_area(parent: Node, name: String, x_min: float, y_min: float, x_max: float, y_max: float, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.name = name
	b.focus_mode = Control.FOCUS_NONE
	for key in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	place(parent, b, x_min, y_min, x_max, y_max)
	b.pressed.connect(on_pressed)
	return b


## A round light that keeps its circle shape. Returns its StyleBoxFlat:
## change style.bg_color to change the light color.
static func circle(parent: Node, name: String, color: Color, x_min: float, y_min: float, x_max: float, y_max: float) -> StyleBoxFlat:
	var box := AspectRatioContainer.new()
	box.name = name
	box.ratio = 1.0
	box.stretch_mode = AspectRatioContainer.STRETCH_FIT
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(parent, box, x_min, y_min, x_max, y_max)
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := flat_style(color, 4096)
	p.add_theme_stylebox_override("panel", sb)
	box.add_child(p)
	return sb


## A status light: a circle with a dark metal ring. Use set_light() to turn it on.
static func led(parent: Node, name: String, x_min: float, y_min: float, x_max: float, y_max: float, ring := 5) -> StyleBoxFlat:
	var sb := circle(parent, name, LED_OFF, x_min, y_min, x_max, y_max)
	sb.set_border_width_all(ring)
	sb.border_color = Color(0, 0, 0, 0.45)
	return sb


## Turns a light on (with a soft glow around it) or off.
static func set_light(style: StyleBoxFlat, color: Color, on := true) -> void:
	style.bg_color = color if on else LED_OFF
	style.shadow_color = Color(color, 0.55) if on else CLEAR
	style.shadow_size = 18 if on else 0


## Dark edges over the whole parent, like a spotlight on the middle.
static func vignette(parent: Node, name: String, strength := 0.85) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([CLEAR, Color(0, 0, 0, 0.0), Color(0, 0, 0, strength)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.46)
	tex.fill_to = Vector2(1.08, 0.46)
	tex.width = 256
	tex.height = 256
	var r := TextureRect.new()
	r.name = name
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(parent, r, 0, 0, 1, 1)
	return r


## Moves a control to new bottom/top fractions (keeps its left/right).
static func set_rows(c: Control, y_min: float, y_max: float) -> void:
	c.set_anchor(SIDE_TOP, 1.0 - y_max, true)
	c.set_anchor(SIDE_BOTTOM, 1.0 - y_min, true)
	c.offset_top = 0
	c.offset_bottom = 0


## Removes all children of a node (used when a mission restarts).
static func clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


static func format_time(seconds: float) -> String:
	var s := int(ceil(maxf(0.0, seconds)))
	return "%02d:%02d" % [s / 60, s % 60]
