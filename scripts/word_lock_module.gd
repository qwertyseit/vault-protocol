# word_lock_module.gd
# -----------------------------------------------------------------------------
# MODULE 4 - WORD LOCK (Mission 3, on the bottom side of the vault)
# A small screen shows a word (or nothing). Six buttons show six words.
# Many words sound the same (STEEL / STEAL, CASH / CACHE, TWO / TOO ...),
# so the Operator has to spell them letter by letter.
#
#   Step 1 (manual): the SCREEN word says which button to READ.
#   Step 2 (manual): the word on that button gives a list; press the button
#                    with the first word of that list that is on the panel.
#
# 3 stages. Right button -> next stage light turns green, new words appear.
# Wrong button -> strike, and the same stage starts again with new words.
# The answer comes from PuzzleRules.word_lock_answer().
# -----------------------------------------------------------------------------
extends "res://scripts/vault_module.gd"

const STAGES := 3
const REFRESH_TIME := 0.35 # the panel goes dark for a moment between stages

var stage := 0
var screen_index := 0
var button_words: Array = [] # 6 words: top left, top right, middle left, middle right, bottom left, bottom right
var answer := 0
var refreshing := false

var screen_label: Label
var word_buttons: Array = []
var stage_lights: Array = []


func display_name() -> String:
	return "WORDS"


func solution_for_debug() -> String:
	return "Word Lock stage 1: press %s (%s)" % [button_words[answer], PuzzleRules.WORD_LOCK_POSITIONS[answer]]


func build(_mission: Dictionary) -> void:
	create_header("WORD LOCK", "Press the right word  •  3 stages")

	var screen := UI.panel(self, "Screen", UI.DARK, 0.08, 0.73, 0.78, 0.885, 16, UI.AMBER_DIM, 4)
	screen_label = UI.text(screen, "Word", "", 92, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, true)

	# 2 columns x 3 rows of word buttons
	var columns := [[0.08, 0.42], [0.44, 0.78]]
	var rows := [[0.53, 0.70], [0.33, 0.50], [0.13, 0.30]]
	for i in 6:
		var c: Array = columns[i % 2]
		var r: Array = rows[i / 2]
		var b := UI.button(self, "Word%d" % (i + 1), "", 54, UI.KEY_FACE, UI.DARK, c[0], r[0], c[1], r[1], _on_word_pressed.bind(i), 16)
		word_buttons.append(b)

	UI.caps(self, "StageCaption", "STAGE", 26, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.80, 0.64, 0.98, 0.70, 4)
	for i in STAGES:
		var y_max := 0.62 - i * 0.15
		stage_lights.append(UI.led(self, "Stage%d" % (i + 1), 0.835, y_max - 0.10, 0.945, y_max, 6))

	_new_words()
	_show_words()


## Picks a new screen word and six different button words for this stage.
func _new_words() -> void:
	screen_index = rng.randi_range(0, PuzzleRules.WORD_LOCK_SCREEN.size() - 1)
	var pool: Array = PuzzleRules.WORD_LOCK_WORDS.duplicate()
	# Shuffle with the module's own random generator (so --seed works).
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	button_words = pool.slice(0, 6)
	answer = PuzzleRules.word_lock_answer(screen_index, button_words)
	if stage > 0 or game.is_playing():
		print("[Vault Protocol] Word Lock stage %d: screen \"%s\" -> press %s (%s)" % [
			stage + 1, PuzzleRules.WORD_LOCK_SCREEN[screen_index], button_words[answer], PuzzleRules.WORD_LOCK_POSITIONS[answer]])


func _show_words() -> void:
	screen_label.text = PuzzleRules.WORD_LOCK_SCREEN[screen_index]
	for i in 6:
		(word_buttons[i] as Button).text = button_words[i]


func _hide_words() -> void:
	screen_label.text = ""
	for b in word_buttons:
		(b as Button).text = ""


func _on_word_pressed(position: int) -> void:
	if not can_act() or refreshing:
		return

	if position == answer:
		UI.set_light(stage_lights[stage], UI.GOOD)
		stage += 1
		if stage == STAGES:
			solve("Word Lock: all 3 stages passed — WORDS disarmed.")
			return
		game.sfx.play("good")
		game.show_status("Word Lock: stage %d / %d passed" % [stage, STAGES], UI.TEXT)
	else:
		strike("Word Lock: %s was WRONG! New words." % button_words[position])

	_refresh()


## Short "screen refresh" so both players notice the new words.
func _refresh() -> void:
	refreshing = true
	_hide_words()
	_new_words()
	var tween := create_tween()
	tween.tween_interval(REFRESH_TIME)
	tween.tween_callback(func():
		refreshing = false
		_show_words()
	)
