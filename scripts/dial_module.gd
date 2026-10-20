# dial_module.gd
# -----------------------------------------------------------------------------
# MODULE 4 - COMBINATION DIAL (Mission 3, on the bottom side of the vault)
# A small screen shows a CODE WORD. The Expert finds the word in the manual
# and reads out 3 numbers (in reverse order if the Vault ID has a vowel).
#
#   TURN the dial: put a finger on it and move it in a circle, like a real
#                  safe dial (or use the - / + buttons for one step).
#   SET          : locks in the number under the amber pointer.
#
# Right number -> the next progress light turns green.
# Wrong number -> strike, and the combination starts again from the first number.
# The answer comes from PuzzleRules.dial_sequence().
# -----------------------------------------------------------------------------
extends "res://scripts/vault_module.gd"

const NUMBERS := 3
const HINT := "Circle a finger on the dial  •  press SET"

var word_index := 0
var sequence: Array = []
var progress := 0

var dial: DialFace
var progress_lights: Array = []


func display_name() -> String:
	return "DIAL"


func solution_for_debug() -> String:
	var parts: Array = []
	for n in sequence:
		parts.append(str(n))
	return "Dial: %s -> %s" % [PuzzleRules.DIAL_WORDS[word_index], " ".join(PackedStringArray(parts))]


func build(_mission: Dictionary) -> void:
	# 1) Random puzzle
	word_index = rng.randi_range(0, PuzzleRules.DIAL_WORDS.size() - 1)
	sequence = PuzzleRules.dial_sequence(word_index, vault_id)

	# 2) UI
	create_header("COMBINATION DIAL", HINT)

	var screen := UI.panel(self, "WordScreen", UI.DARK, 0.20, 0.765, 0.80, 0.89, 16, UI.AMBER_DIM, 4)
	UI.caps(screen, "Caption", "CODE WORD", 20, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0, 0.70, 1, 0.97, 4)
	UI.text(screen, "Word", PuzzleRules.DIAL_WORDS[word_index], 76, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0, 0.02, 1, 0.78, true)

	# The dial stays round on any screen.
	var box := AspectRatioContainer.new()
	box.name = "DialArea"
	box.ratio = 1.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(self, box, 0.17, 0.185, 0.83, 0.755)
	dial = DialFace.new()
	dial.name = "Dial"
	box.add_child(dial)
	dial.number_changed.connect(_on_number_changed)

	UI.button(self, "Minus", "-", 84, UI.PANEL_LIGHT, UI.TEXT, 0.03, 0.40, 0.15, 0.54, _step.bind(-1), 18)
	UI.button(self, "Plus", "+", 84, UI.PANEL_LIGHT, UI.TEXT, 0.85, 0.40, 0.97, 0.54, _step.bind(1), 18)

	UI.caps(self, "StepsCaption", "COMBINATION", 22, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.06, 0.155, 0.46, 0.185, 3)
	for i in NUMBERS:
		var x := 0.09 + i * 0.12
		progress_lights.append(UI.led(self, "Step%d" % (i + 1), x, 0.09, x + 0.09, 0.155, 6))

	UI.button(self, "SetButton", "SET", 56, UI.AMBER, UI.DARK, 0.56, 0.085, 0.94, 0.175, _on_set, 20)


func _on_set() -> void:
	if not can_act():
		return
	var n := dial.selected()
	if n == sequence[progress]:
		UI.set_light(progress_lights[progress], UI.GOOD)
		progress += 1
		if progress == NUMBERS:
			dial.enabled = false
			solve("Combination accepted — DIAL disarmed.")
		else:
			game.sfx.play("good")
			game.show_status("Dial: %d accepted (%d / %d)" % [n, progress, NUMBERS], UI.TEXT)
	else:
		progress = 0
		for light in progress_lights:
			UI.set_light(light, UI.LED_OFF, false)
		strike("Dial: %d was WRONG! Start the combination again." % n)


func _step(direction: int) -> void:
	if can_act():
		dial.step_by(direction)


func _on_number_changed(_n: int) -> void:
	if can_act():
		game.sfx.play("tick")


## The 3D vault asks this before a touch: true = the finger turns the dial,
## so the vault must not spin.
func wants_drag_at(pixel: Vector2) -> bool:
	return can_act() and dial.contains(pixel)


## Called by the 3D vault when the touch was cancelled (second finger, pause).
func cancel_touch() -> void:
	dial.cancel()


# =============================================================================
# The dial itself: drawn with code, turned by moving a finger around it.
# =============================================================================
class DialFace extends Control:
	signal number_changed(n: int)

	const COUNT := 10
	const STEP := TAU / COUNT
	const UIRef = preload("res://scripts/ui_factory.gd")

	var angle := 0.0 # turn of the dial in radians (clockwise)
	var enabled := true
	var _dragging := false
	var _last_angle := 0.0
	var _shown := 0
	var _tween: Tween

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	## The number under the pointer at the top.
	func selected() -> int:
		return posmod(int(round(-angle / STEP)), COUNT)

	## True if a point (in the face screen's pixels) is on the dial.
	func contains(pixel: Vector2) -> bool:
		var r := get_global_rect()
		return r.has_point(pixel) and pixel.distance_to(r.get_center()) <= _radius() * 1.05

	## +1 = next number, -1 = previous number.
	func step_by(direction: int) -> void:
		_dragging = false
		_animate_to(round(angle / STEP) * STEP - direction * STEP)

	func cancel() -> void:
		if _dragging:
			_dragging = false
			_snap()

	func _center() -> Vector2:
		return size * 0.5 + Vector2(0, size.y * 0.035)

	func _radius() -> float:
		return minf(size.x, size.y) * 0.43

	func _gui_input(event: InputEvent) -> void:
		if not enabled:
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
			if mb.pressed and mb.position.distance_to(_center()) <= _radius() * 1.05:
				_dragging = true
				_last_angle = (mb.position - _center()).angle()
				if _tween != null:
					_tween.kill()
				accept_event()
			elif not mb.pressed and _dragging:
				_dragging = false
				_snap()
		elif event is InputEventMouseMotion and _dragging:
			var mm := event as InputEventMouseMotion
			var a := (mm.position - _center()).angle()
			angle += wrapf(a - _last_angle, -PI, PI)
			_last_angle = a
			_check_number()
			queue_redraw()

	func _snap() -> void:
		_animate_to(round(angle / STEP) * STEP)

	func _animate_to(target: float) -> void:
		if _tween != null:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_method(_set_angle, angle, target, 0.12).set_ease(Tween.EASE_OUT)

	func _set_angle(value: float) -> void:
		angle = value
		_check_number()
		queue_redraw()

	func _check_number() -> void:
		var s := selected()
		if s != _shown:
			_shown = s
			number_changed.emit(s)

	static func _dir(a: float) -> Vector2:
		return Vector2(sin(a), -cos(a)) # 0 = up, clockwise

	func _draw() -> void:
		var c := _center()
		var r := _radius()
		var font := UIRef.bold_font()

		# Ring and dial face
		draw_circle(c, r * 1.03, Color(0.04, 0.05, 0.06))
		draw_circle(c, r * 0.95, Color(0.22, 0.24, 0.28))
		draw_circle(c, r * 0.90, Color(0.17, 0.19, 0.22))

		# Tick marks (they turn with the dial)
		for i in COUNT * 5:
			var a := angle + i * STEP / 5.0
			var big := i % 5 == 0
			var inner := r * (0.76 if big else 0.82)
			draw_line(c + _dir(a) * inner, c + _dir(a) * r * 0.89, Color(0.75, 0.78, 0.82) if big else Color(0.45, 0.48, 0.52), 6.0 if big else 3.0, true)

		# Numbers (upright so they are easy to read)
		var font_size := int(r * 0.20)
		var top := selected()
		for k in COUNT:
			var a := angle + k * STEP
			var p := c + _dir(a) * r * 0.58
			var txt := str(k)
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var col := UIRef.AMBER if k == top and not _dragging else UIRef.TEXT
			draw_string(font, p + Vector2(-w * 0.5, font_size * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

		# Knob with grip lines in the middle
		draw_circle(c, r * 0.36, Color(0.07, 0.08, 0.09))
		draw_circle(c, r * 0.31, Color(0.28, 0.30, 0.34))
		for i in 8:
			var a := angle + i * TAU / 8.0
			draw_line(c + _dir(a) * r * 0.14, c + _dir(a) * r * 0.28, Color(0.16, 0.17, 0.19), 7.0, true)
		draw_circle(c, r * 0.08, UIRef.AMBER if enabled else UIRef.GOOD)

		# Fixed amber pointer above the dial
		var tip := c + Vector2(0, -r * 0.93)
		var pointer := PackedVector2Array([tip + Vector2(-r * 0.09, -r * 0.13), tip + Vector2(r * 0.09, -r * 0.13), tip])
		draw_colored_polygon(pointer, UIRef.AMBER)
