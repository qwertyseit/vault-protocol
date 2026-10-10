# button_module.gd
# -----------------------------------------------------------------------------
# MODULE 2 - OVERRIDE BUTTON
# A big colored button with a label (OPEN / LOCK / HOLD / RESET).
#
#   TAP  = press and let go quickly (before the light turns on).
#   HOLD = keep pressing. After 0.5 s a LIGHT turns on (random color) and the
#          PIN COUNTER starts counting 1,2,...,9,1,2,... Let go when the
#          counter shows the number the manual gives for that light color.
#
# Which one is correct: PuzzleRules.button_should_hold() / release_number().
# -----------------------------------------------------------------------------
extends "res://scripts/vault_module.gd"

const HOLD_THRESHOLD := 0.5 # seconds until a press counts as HOLD
const COUNTER_STEP := 0.8 # seconds per counter number
const RELEASE_GRACE := 0.15 # letting go right after the number changed also accepts the previous number

const IDLE_HINT := "Quick tap = TAP   •   Keep pressing = HOLD"
const HOLDING_HINT := "HOLDING — let go on the right number"

var color := 0
var label := 0
var should_hold := false

var big_button: Button
var light_style: StyleBoxFlat
var counter_label: Label
var hint_label: Label

var pressing := false # finger is on the button
var holding := false # press lasted longer than HOLD_THRESHOLD
var press_time := 0.0
var counter_timer := 0.0
var counter := 0
var previous_counter := 0 # number shown just before the last change
var light := 0


func display_name() -> String:
	return "BUTTON"


func solution_for_debug() -> String:
	if should_hold:
		return "Button: HOLD (release on WHITE=3, BLUE=6, YELLOW=2, RED=8)"
	return "Button: TAP"


func build(_mission: Dictionary) -> void:
	# 1) Random puzzle
	color = rng.randi_range(0, 3)
	label = rng.randi_range(0, 3)
	should_hold = PuzzleRules.button_should_hold(color, label, vault_id)

	# 2) UI
	hint_label = create_header("OVERRIDE BUTTON", IDLE_HINT)

	# The square box keeps the button round on any screen.
	var box := AspectRatioContainer.new()
	box.name = "ButtonArea"
	box.ratio = 1.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(self, box, 0.15, 0.40, 0.85, 0.89)

	var bg := UI.button_color(color)
	var dark_text := color == PuzzleRules.ButtonColor.WHITE or color == PuzzleRules.ButtonColor.YELLOW
	big_button = Button.new()
	big_button.name = "BigButton"
	big_button.text = PuzzleRules.BUTTON_LABEL_NAMES[label]
	big_button.focus_mode = Control.FOCUS_NONE
	big_button.keep_pressed_outside = true
	# Round button in a dark metal ring; the ring gets thicker when pressed.
	var normal := UI.flat_style(bg, 4096)
	normal.set_border_width_all(26)
	normal.border_color = Color(0.05, 0.06, 0.07)
	normal.shadow_color = Color(0, 0, 0, 0.5)
	normal.shadow_size = 14
	normal.shadow_offset = Vector2(0, 8)
	var pressed := UI.flat_style(bg.darkened(0.25), 4096)
	pressed.set_border_width_all(36)
	pressed.border_color = Color(0.05, 0.06, 0.07)
	for key in ["normal", "hover"]:
		big_button.add_theme_stylebox_override(key, normal)
	for key in ["pressed", "hover_pressed"]:
		big_button.add_theme_stylebox_override(key, pressed)
	big_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	big_button.add_theme_font_override("font", UI.bold_font())
	big_button.add_theme_font_size_override("font_size", 96)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		big_button.add_theme_color_override(key, UI.DARK if dark_text else Color.WHITE)
	box.add_child(big_button)
	big_button.button_down.connect(_on_pressed)
	big_button.button_up.connect(_on_released)
	visibility_changed.connect(_on_visibility_changed)

	# Light (left) and pin counter (right)
	var light_block := UI.area(self, "LightBlock", 0.08, 0.11, 0.46, 0.36)
	UI.text(light_block, "Caption", "LIGHT", 32, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0, 0.80, 1, 1, true)
	light_style = UI.led(light_block, "Light", 0.1, 0.06, 0.9, 0.74, 10)

	var counter_block := UI.area(self, "CounterBlock", 0.54, 0.11, 0.92, 0.36)
	UI.text(counter_block, "Caption", "PIN COUNTER", 32, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0, 0.80, 1, 1, true)
	var display := UI.panel(counter_block, "Display", UI.DARK, 0.12, 0.06, 0.88, 0.74, 16, UI.AMBER_DIM, 4)
	counter_label = UI.text(display, "Digit", "-", 120, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, true)


func _process(delta: float) -> void:
	if not pressing:
		return
	if not can_act():
		_reset_press() # mission ended while holding
		return

	press_time += delta

	if not holding and press_time >= HOLD_THRESHOLD:
		_start_hold()

	if holding:
		counter_timer += delta
		while counter_timer >= COUNTER_STEP: # "while" keeps it right even on a slow frame
			counter_timer -= COUNTER_STEP
			previous_counter = counter
			counter = counter % 9 + 1 # 1..9 then back to 1
			counter_label.text = str(counter)
			game.sfx.play("tick")


func _on_pressed() -> void:
	if not can_act():
		return
	pressing = true
	holding = false
	press_time = 0.0
	game.sfx.play("click")


func _start_hold() -> void:
	holding = true
	light = rng.randi_range(0, 3)
	UI.set_light(light_style, UI.light_color(light))
	counter = 1
	previous_counter = 1
	counter_timer = 0.0
	counter_label.text = "1"
	hint_label.text = HOLDING_HINT
	print("[Vault Protocol] Button light: %s -> release on %d" % [PuzzleRules.LIGHT_NAMES[light], PuzzleRules.release_number(light)])


func _on_released() -> void:
	if not pressing:
		return
	var was_holding := holding
	var released_on := counter
	# The finger may have lifted while the player still saw the previous
	# number (the counter changed in the same frame). Be fair about it.
	var just_changed := counter_timer < RELEASE_GRACE
	var shown_before := previous_counter
	_reset_press()

	if not can_act():
		return # time ran out while holding, etc.

	if not was_holding:
		# The player TAPPED.
		if not should_hold:
			solve("Quick TAP — correct! BUTTON disarmed.")
		else:
			strike("Wrong! This button had to be HELD, not tapped.")
	else:
		# The player HELD and let go on 'released_on'.
		var target := PuzzleRules.release_number(light)
		if released_on != target and just_changed and shown_before == target:
			released_on = target
		if not should_hold:
			strike("Wrong! This button needed a quick TAP.")
		elif released_on == target:
			solve("Released on %d — correct! BUTTON disarmed." % released_on)
		else:
			strike("Released on %d — wrong number!" % released_on)


## Called by the 3D vault when a touch turned out to be a spin, not a press.
func cancel_touch() -> void:
	_reset_press()


func _on_visibility_changed() -> void:
	# Example: the player switched to another module tab while holding.
	if not is_visible_in_tree() and pressing:
		_reset_press()


func _reset_press() -> void:
	pressing = false
	holding = false
	press_time = 0.0
	counter_timer = 0.0
	counter = 0
	if light_style != null:
		UI.set_light(light_style, UI.LED_OFF, false)
	if counter_label != null:
		counter_label.text = "-"
	if hint_label != null:
		hint_label.text = IDLE_HINT
