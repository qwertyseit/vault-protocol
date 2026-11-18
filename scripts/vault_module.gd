# vault_module.gd
# -----------------------------------------------------------------------------
# Base class for every security module (Wires, Button, Keypad, Word Lock).
# A module:
#   1) builds its own UI inside itself (build),
#   2) checks the player's action against PuzzleRules,
#   3) calls solve(...) or strike(...). The GameManager handles the rest
#      (strike counter, sounds, status message, win/lose).
#
# Side timers: during a mission every module starts SEALED behind a shutter
# that shows its name and its time. Tapping the shutter asks the GameManager
# to open the side: the side timer starts and keeps running even when the
# vault is turned to another side (v0.5). A small timer in the bottom-left
# corner of the open side shows how much time this side has left.
# To add a new module: create a script that extends this one.
# -----------------------------------------------------------------------------
extends Control

const UI = preload("res://scripts/ui_factory.gd")
const PuzzleRules = preload("res://scripts/puzzle_rules.gd")
const VaultId = preload("res://scripts/vault_id.gd")

var game: Node # the GameManager (main.gd)
var vault_id: VaultId
var rng: RandomNumberGenerator
var is_solved := false
var is_open := true # false while the shutter covers the module
var side_time := 0.0 # seconds this side gets once it is opened
var time_left := 0.0 # counts down while the side is open (set by the GameManager)

var _shutter: Button
var _hint_label: Label
var _timer_chip: Control
var _timer_label: Label
var _shown_second := -1


## Called once by the GameManager right after the module is created.
func init_module(p_game: Node, mission: Dictionary, p_vault_id: VaultId, p_rng: RandomNumberGenerator) -> void:
	game = p_game
	vault_id = p_vault_id
	rng = p_rng
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build(mission)


## Name shown on the module tab, e.g. "WIRES". Override in each module.
func display_name() -> String:
	return "MODULE"


## The correct answer as text - printed to the Output panel for testing.
func solution_for_debug() -> String:
	return ""


## Create the random puzzle and its UI. Override in each module.
func build(_mission: Dictionary) -> void:
	pass


## True while the player is allowed to interact with this module.
func can_act() -> bool:
	return not is_solved and is_open and game != null and game.is_playing()


func solve(message: String) -> void:
	if is_solved:
		return
	is_solved = true
	if _timer_chip != null:
		_timer_chip.visible = false
	_show_disarmed_banner()
	game.on_module_solved(self, message)


func strike(message: String) -> void:
	game.on_strike(self, message)


## Common header: title on top, hint at the bottom. Returns the hint label.
func create_header(title: String, hint: String) -> Label:
	var band := UI.panel(self, "TitleBand", Color(0, 0, 0, 0.35), 0.08, 0.905, 0.92, 0.985, 16)
	UI.caps(band, "Title", title, 38, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0.02, 0, 0.98, 1, 5)
	_hint_label = UI.text(self, "Hint", hint, 34, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.01, 0.96, 0.08)
	return _hint_label


# =============================================================================
# Shutter (side timer)
# =============================================================================

## Seals the module: a metal shutter with the module name and its side time.
## The whole shutter is one big button.
func add_shutter(seconds: float) -> void:
	side_time = seconds
	is_open = false
	_shutter = UI.touch_area(self, "Shutter", 0, 0, 1, 1, _on_shutter_tapped)
	UI.panel(_shutter, "Plate", UI.PANEL_DARK, 0, 0, 1, 1, 22, UI.AMBER_DIM, 4)
	# hazard stripes along the top and the bottom edge
	for y in [[0.90, 0.97], [0.03, 0.10]]:
		var band := UI.area(_shutter, "Stripes", 0.04, y[0], 0.96, y[1])
		band.clip_contents = true
		UI.rect(band, "Base", Color(UI.AMBER, 0.85), 0, 0, 1, 1)
		var x := -60.0
		while x < 1000.0:
			var bar := ColorRect.new()
			bar.color = UI.DARK
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.size = Vector2(34, 180)
			bar.position = Vector2(x, -60)
			bar.rotation = deg_to_rad(35.0)
			band.add_child(bar)
			x += 84.0
	UI.caps(_shutter, "Name", display_name(), 120, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.66, 0.96, 0.82, 14)
	UI.caps(_shutter, "TimeCaption", "SIDE TIMER", 34, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.585, 0.96, 0.64, 8)
	var box := UI.panel(_shutter, "TimeBox", UI.DARK, 0.24, 0.40, 0.76, 0.58, 22, UI.AMBER_DIM, 4)
	UI.text(box, "Time", UI.format_time(seconds), 130, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, true)
	var pill := UI.panel(_shutter, "Pill", UI.AMBER, 0.20, 0.17, 0.80, 0.31, 4096)
	UI.caps(pill, "Text", "TAP TO OPEN", 50, UI.DARK, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, 6)


func _on_shutter_tapped() -> void:
	if is_open or game == null or not game.is_playing():
		return
	game.request_open_side(self)


## Called by the GameManager: the shutter slides up and the module can be used.
func open_side() -> void:
	is_open = true
	time_left = side_time
	# the side's own timer sits in the hint line, the hint moves to the right
	_timer_chip = UI.panel(self, "SideTimer", UI.DARK, 0.03, 0.012, 0.25, 0.078, 14, UI.AMBER_DIM, 3)
	_timer_label = UI.text(_timer_chip, "Time", UI.format_time(time_left), 44, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, true)
	if _hint_label != null:
		_hint_label.anchor_left = 0.28
		_hint_label.anchor_right = 0.97
		_hint_label.add_theme_font_size_override("font_size", 29)
	if _shutter == null:
		return
	var s := _shutter
	_shutter = null
	s.disabled = true
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "position:y", s.position.y - s.size.y, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(s, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(s.queue_free)


## The side's own timer (bottom-left corner of the open side). The label is
## changed only when the shown second changes.
func show_time_left() -> void:
	if _timer_label == null:
		return
	var whole := int(ceil(time_left))
	if whole == _shown_second:
		return
	_shown_second = whole
	_timer_label.text = UI.format_time(time_left)
	_timer_label.add_theme_color_override("font_color", UI.BAD if time_left <= 20.0 else UI.AMBER)


## Dims the module and slams a green "DISARMED" stamp on it.
func _show_disarmed_banner() -> void:
	UI.rect(self, "Dim", Color(0.02, 0.05, 0.04, 0.55), 0, 0, 1, 1)
	var stamp := UI.panel(self, "DisarmedStamp", Color(0.04, 0.20, 0.11, 0.94), 0.10, 0.40, 0.90, 0.60, 22, UI.GOOD, 9)
	UI.caps(stamp, "Text", "DISARMED", 92, UI.GOOD, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, 8)
	stamp.pivot_offset = stamp.size * 0.5
	stamp.rotation = deg_to_rad(-7.0)
	stamp.scale = Vector2.ONE * 1.5
	stamp.modulate.a = 0.0
	var tw := stamp.create_tween().set_parallel(true)
	tw.tween_property(stamp, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_IN)
	tw.tween_property(stamp, "modulate:a", 1.0, 0.12)
