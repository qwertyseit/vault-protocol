# keypad_module.gd
# -----------------------------------------------------------------------------
# MODULE 3 - SYMBOL KEYPAD
# Four keys with strange symbols. Every symbol has a code number in the manual.
# Press the keys in the order given by PuzzleRules.keypad_order():
#   no vowel in the Vault ID -> lowest code first; vowel -> highest code first.
# Correct key -> its light turns green. Wrong key -> strike (progress is kept).
# -----------------------------------------------------------------------------
extends "res://scripts/vault_module.gd"

const KEY_COUNT := 4

var key_symbols: Array = [] # symbol index on each key position (0..3)
var press_order: Array = [] # key positions in the correct order
var progress := 0 # how many keys are already correct
var key_done: Array = []

var key_styles: Array = [] # background StyleBox of each key
var light_styles: Array = [] # small light on each key


func display_name() -> String:
	return "KEYPAD"


func solution_for_debug() -> String:
	var parts := []
	for pos in press_order:
		var sym: int = key_symbols[pos]
		parts.append("%s(%d)" % [PuzzleRules.SYMBOL_GLYPHS[sym], PuzzleRules.SYMBOL_CODES[sym]])
	return "Keypad: " + " -> ".join(parts)


func build(_mission: Dictionary) -> void:
	# 1) Random puzzle: 4 different symbols out of the 16 in the manual.
	var all := []
	for i in PuzzleRules.SYMBOL_GLYPHS.size():
		all.append(i)
	# Shuffle with our own RNG (Fisher-Yates)
	for i in range(all.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = all[i]
		all[i] = all[j]
		all[j] = tmp
	key_symbols = all.slice(0, KEY_COUNT)
	press_order = PuzzleRules.keypad_order(key_symbols, vault_id)
	for i in KEY_COUNT:
		key_done.append(false)

	# 2) UI: a square 2x2 grid that stays square on any screen.
	create_header("SYMBOL KEYPAD", "Press the 4 keys in the right order")

	var box := AspectRatioContainer.new()
	box.name = "KeyArea"
	box.ratio = 1.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(self, box, 0.08, 0.10, 0.92, 0.89)
	var grid := Control.new()
	grid.name = "Grid"
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(grid)

	# position: 0 = top-left, 1 = top-right, 2 = bottom-left, 3 = bottom-right
	var rects := [
		[0.02, 0.52, 0.48, 0.98],
		[0.52, 0.52, 0.98, 0.98],
		[0.02, 0.02, 0.48, 0.48],
		[0.52, 0.02, 0.98, 0.48],
	]

	for i in KEY_COUNT:
		var r: Array = rects[i]
		var key := UI.button(grid, "Key%d" % (i + 1), "", 10, UI.KEY_FACE, UI.DARK, r[0], r[1], r[2], r[3], _on_key_pressed.bind(i))
		key_styles.append(key.get_meta("style"))
		UI.text(key, "Symbol", PuzzleRules.SYMBOL_GLYPHS[key_symbols[i]], 190, UI.DARK, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 0.84)
		light_styles.append(UI.led(key, "Light", 0.40, 0.83, 0.60, 0.96, 4))


func _on_key_pressed(pos: int) -> void:
	if not can_act() or key_done[pos]:
		return

	if pos == press_order[progress]:
		key_done[pos] = true
		UI.set_light(light_styles[pos], UI.GOOD)
		progress += 1
		if progress == KEY_COUNT:
			solve("All 4 symbols accepted — KEYPAD disarmed.")
		else:
			game.sfx.play("good")
			game.show_status("Key accepted (%d / %d)" % [progress, KEY_COUNT], UI.TEXT)
	else:
		strike("Wrong key! The order is not correct.")
		_flash_key(pos)


func _flash_key(pos: int) -> void:
	var style: StyleBoxFlat = key_styles[pos]
	style.bg_color = UI.BAD
	# A tween that belongs to this module: it is stopped automatically
	# if the module is removed (e.g. the player presses RETRY).
	var tween := create_tween()
	tween.tween_interval(0.35)
	tween.tween_callback(func(): style.bg_color = UI.KEY_FACE)
