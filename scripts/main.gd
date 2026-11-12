# main.gd  (the GameManager)
# -----------------------------------------------------------------------------
# The "brain" of Vault Protocol. Attached to the root node of main.tscn.
#   * builds the UI (menu, HUD, result screen) and the 3D vault from code,
#   * runs the game states: MENU -> PLAYING -> RESULT -> (Retry / Next / Menu),
#   * runs the SIDE TIMERS and counts strikes (3 strikes = alarm = lose),
#   * puts the modules of the selected mission on the sides of the vault.
#
# Side timers (v0.4, from the Assignment 3 feedback): every module starts
# sealed. The Operator taps a side to open it -> that side's timer starts and
# the vault locks on it until it is disarmed. Side timer at 00:00 = alarm.
# Best clear times are saved per mission (game_progress.gd).
#
# Sides of the vault:  FRONT = timer display,  RIGHT = Wires,  BACK = Button,
#                      LEFT = Keypad (Mission 2),  TOP = Vault ID plate.
# In the menu the same vault slowly spins behind the title (showcase mode).
# Mission 3 adds the Word Lock on the BOTTOM side.
#
# Also here: the pause menu (the game pauses by itself when the app goes to
# the background; the Android back button pauses / goes back), the Settings
# screen (saved on the phone), the 3-page How to play screen and the
# performance overlay (perf_monitor.gd).
# -----------------------------------------------------------------------------
extends Control

const UI = preload("res://scripts/ui_factory.gd")
const VaultId = preload("res://scripts/vault_id.gd")
const MissionData = preload("res://scripts/mission_data.gd")
const SoundFx = preload("res://scripts/sound_fx.gd")
const Vault3D = preload("res://scripts/vault_3d.gd")
const WiresModule = preload("res://scripts/wires_module.gd")
const ButtonModule = preload("res://scripts/button_module.gd")
const KeypadModule = preload("res://scripts/keypad_module.gd")
const WordLockModule = preload("res://scripts/word_lock_module.gd")
const GameSettings = preload("res://scripts/game_settings.gd")
const GameProgress = preload("res://scripts/game_progress.gd")
const PerfMonitor = preload("res://scripts/perf_monitor.gd")

enum State { MENU, PLAYING, PAUSED, RESULT }

const MAX_STRIKES := 3
const RESULT_DELAY := 0.9 # pause so players see their last action
const STATUS_TIME := 5.0 # seconds a message stays on screen before it fades

var state: State = State.MENU
var sfx: Node

# ---- mission state ----
var rng := RandomNumberGenerator.new()
var mission_index := 0
var mission: Dictionary
var vault_id: VaultId
var active_module: Control = null # the side that is open right now (or null)
var side_time_left := 0.0 # timer of the open side
var mission_time := 0.0 # time played in this mission (for the records)
var strikes := 0
var last_whole_second := -1
var progress: GameProgress
var new_record := false
var modules: Array = []
var module_faces: Array = [] # which vault side each module is on
var flow_token := 0 # changes on every restart/menu, cancels pending result screens

# ---- UI references ----
var safe_root: Control
var menu_screen: Control
var game_screen: Control
var result_screen: Control
var vault: Vault3D # the 3D vault (vault_3d.gd)
var timer_label: Label # small timer in the HUD
var display_timer_label: Label # big timer on the front of the vault
var hud_ghost: Label # dim "88:88" behind the HUD timer (hidden while no side is open)
var display_ghost: Label # the same on the front of the vault
var status_label: Label
var status_style: StyleBoxFlat
var status_box: Control
var status_time := 0.0 # seconds left before the message fades
var mission_records: Array = [] # [time Label, caption Label] on every menu card
var perf: Control # perf_monitor.gd overlay
var strike_lights: Array = [] # HUD
var display_strike_lights: Array = [] # front of the vault
var result_card_style: StyleBoxFlat
var result_caption: Label
var result_title: Label
var result_flavor: Label
var result_time: Label
var result_strikes: Label
var result_modules: Label
var result_record: Label
var retry_button: Button
var next_mission_button: Button
var result_menu_button: Button
var flash_rect: ColorRect
var flash_alpha := 0.0
var flash_color := Color.RED

# ---- pause / settings / how to play ----
var settings: GameSettings
var pause_screen: Control
var pause_caption: Label
var pause_info: Label
var settings_screen: Control
var sound_toggle: Button
var vibration_toggle: Button
var perf_toggle: Button
var reset_records_button: Button
var reset_armed := false
var spin_buttons: Array = []
var howto_screen: Control
var howto_pages: Array = []
var howto_dots: Array = []
var howto_page := 0
var howto_back: Button
var howto_next: Button


# =============================================================================
# Godot callbacks
# =============================================================================
func _ready() -> void:
	rng.randomize()
	# Testing help: run with "-- --seed=123" to get the same puzzles every time.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			rng.seed = int(arg.substr(7))
	DisplayServer.screen_set_keep_on(true) # players talk a lot :)
	get_tree().quit_on_go_back = false # the Android back button pauses / goes back instead
	settings = GameSettings.new()
	settings.load_settings()
	progress = GameProgress.new()
	progress.load_progress()
	sfx = SoundFx.new()
	sfx.name = "SoundFx"
	add_child(sfx)

	_build_ui()
	vault.rotation_blocked.connect(_on_rotation_blocked)
	_apply_settings()
	get_viewport().size_changed.connect(_apply_layout)
	_apply_layout()
	show_menu()
	if not settings.tutorial_seen:
		open_howto() # first start: explain the game


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			# A call, the notification shade, another app: never lose time.
			if state == State.PLAYING:
				pause_game()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_on_back_button()


func _process(delta: float) -> void:
	_update_flash(delta)
	_update_status_fade(delta)

	if state != State.PLAYING:
		return

	mission_time += delta
	if active_module != null:
		side_time_left -= delta
		if side_time_left <= 0.0:
			side_time_left = 0.0
			_update_timer_labels()
			_end_mission(false, "The %s side ran out of time!" % active_module.display_name())
			return
	_update_timer_labels()


# =============================================================================
# Game flow
# =============================================================================
func is_playing() -> bool:
	return state == State.PLAYING


func show_menu() -> void:
	flow_token += 1
	state = State.MENU
	vault.interactive = false
	vault.locked = false
	active_module = null
	pause_screen.visible = false
	settings_screen.visible = false
	perf.visible = false
	vault.set_vault_hidden(false)
	_clear_mission()
	_refresh_mission_records()
	_build_showcase()
	vault.set_showcase(true)
	vault.set_active(false) # the menu panels never change: draw them once
	menu_screen.visible = true
	game_screen.visible = false
	result_screen.visible = false
	_fade_in(menu_screen)


func start_mission(index: int) -> void:
	flow_token += 1
	_clear_mission()

	mission_index = index
	mission = MissionData.get_mission(index)
	vault_id = VaultId.new(VaultId.random_code(rng))
	active_module = null
	side_time_left = 0.0
	mission_time = 0.0
	strikes = 0
	last_whole_second = -1
	new_record = false
	vault.locked = false

	for light in strike_lights:
		UI.set_light(light, UI.LED_OFF, false)

	_build_display_face()
	_build_plate_face()
	_create_module(WiresModule, Vault3D.Face.RIGHT)
	_create_module(ButtonModule, Vault3D.Face.BACK)
	if mission["has_keypad"]:
		_create_module(KeypadModule, Vault3D.Face.LEFT)
	else:
		_build_empty_face(Vault3D.Face.LEFT)
	if mission["has_word_lock"]:
		_create_module(WordLockModule, Vault3D.Face.BOTTOM)
	else:
		vault.show_sticker()

	show_status("Read the VAULT ID on top to your Expert first. Then tap a side to open it.", UI.MUTED, 12.0)

	menu_screen.visible = false
	result_screen.visible = false
	pause_screen.visible = false
	settings_screen.visible = false
	vault.set_vault_hidden(false)
	game_screen.visible = true
	_fade_in(game_screen)
	vault.set_showcase(false)
	vault.reset_view()
	vault.set_active(true)
	vault.interactive = true
	state = State.PLAYING
	perf.visible = settings.perf_monitor
	perf.reset_test()
	_update_timer_labels()
	sfx.play("start")

	# Testing help: the answers are printed to the Output panel (not visible on the phone).
	var debug_text := "[Vault Protocol] %s | Vault ID %s" % [mission["title"], vault_id.code]
	for m in modules:
		debug_text += "\n  " + m.solution_for_debug()
	print(debug_text)


func _create_module(script: GDScript, face: int) -> void:
	var module: Control = script.new()
	module.name = module.display_name()
	UI.place(vault.face_holder(face), module, 0, 0, 1, 1)
	module.init_module(self, mission, vault_id, rng)
	module.add_shutter(MissionData.side_time(mission, module.display_name()))
	modules.append(module)
	module_faces.append(face)
	vault.set_led(face, true, UI.BAD)


func _clear_mission() -> void:
	modules.clear()
	module_faces.clear()
	display_timer_label = null
	display_ghost = null
	display_strike_lights.clear()
	if vault != null:
		vault.clear_faces()


## Menu: dress the vault with demo panels (nobody can press them).
func _build_showcase() -> void:
	var demo_rng := RandomNumberGenerator.new()
	demo_rng.seed = 2401
	mission = MissionData.get_mission(MissionData.count() - 1)
	vault_id = VaultId.new("VPX-024")
	_build_display_face()
	display_timer_label.text = "--:--"
	display_timer_label.add_theme_color_override("font_color", UI.MUTED)
	display_ghost.visible = false
	_build_plate_face()
	vault.show_sticker()
	var demo := [[WiresModule, Vault3D.Face.RIGHT], [ButtonModule, Vault3D.Face.BACK], [KeypadModule, Vault3D.Face.LEFT]]
	for d in demo:
		var module: Control = (d[0] as GDScript).new()
		UI.place(vault.face_holder(d[1]), module, 0, 0, 1, 1)
		module.init_module(self, mission, vault_id, demo_rng)
		vault.set_led(d[1], true, UI.BAD)


## Called by a module when the Operator taps its shutter.
func request_open_side(module: Control) -> void:
	if not is_playing() or module.is_open:
		return
	if active_module != null:
		show_status("Finish the %s side first." % active_module.display_name(), UI.AMBER)
		vault.shake(0.3)
		sfx.play("click")
		return

	active_module = module
	side_time_left = module.side_time
	last_whole_second = -1
	module.open_side()
	vault.snap_to_face(module_faces[modules.find(module)])
	vault.locked = true
	vault.set_led(module_faces[modules.find(module)], true, UI.AMBER)
	show_status("%s is open. The vault is locked until you disarm it." % module.display_name(), UI.TEXT)
	sfx.play("start")
	_update_timer_labels()


## The player tried to turn the vault while a side is open.
func _on_rotation_blocked() -> void:
	if active_module == null or not is_playing():
		return
	show_status("Locked: finish the %s side first." % active_module.display_name(), UI.AMBER)
	vault.shake(0.25)
	sfx.play("click")


## Called by a module when the player made a wrong action.
func on_strike(_module: Control, message: String) -> void:
	if not is_playing():
		return

	strikes += 1
	UI.set_light(strike_lights[strikes - 1], UI.BAD)
	UI.set_light(display_strike_lights[strikes - 1], UI.BAD)
	sfx.play("strike")
	_flash(UI.BAD, 0.45)
	vault.shake(1.0)
	if settings.vibration:
		Input.vibrate_handheld(300)
	show_status("%s\nSTRIKE %d / %d" % [message, strikes, MAX_STRIKES], UI.BAD)

	if strikes >= MAX_STRIKES:
		_end_mission(false, "Three strikes — the alarm went off!")


## Called by a module when it was solved correctly.
func on_module_solved(module: Control, message: String) -> void:
	if not is_playing():
		return

	var index := modules.find(module)
	if index >= 0:
		vault.set_led(module_faces[index], true, UI.GOOD)
	if module == active_module:
		active_module = null # the side is done: the vault can turn again
		vault.locked = false
	sfx.play("solved")
	_flash(UI.GOOD, 0.25)
	vault.pop()
	var left := modules.size() - _count_solved()
	if left > 0:
		show_status("%s\nTurn the vault: %d %s left." % [message, left, "side" if left == 1 else "sides"], UI.GOOD)
	else:
		show_status(message, UI.GOOD)
	_update_timer_labels()

	if _count_solved() == modules.size():
		_end_mission(true, "")


func _end_mission(won: bool, reason: String) -> void:
	state = State.RESULT # stops the timer and blocks all modules
	vault.interactive = false
	vault.locked = false
	timer_label.visible = true # never end on a "blink off" frame
	if display_timer_label != null:
		display_timer_label.visible = true
	if won:
		new_record = progress.submit_clear(mission_index, mission_time, strikes)
	sfx.play("win" if won else "alarm")
	_show_result_after_delay(won, reason)


func _show_result_after_delay(won: bool, reason: String) -> void:
	var token := flow_token
	await get_tree().create_timer(RESULT_DELAY).timeout
	if token != flow_token:
		return # the player already pressed MENU / RETRY

	var color := UI.GOOD if won else UI.BAD
	result_caption.text = "MISSION %d  •  %s" % [mission_index + 1, mission["subtitle"]]
	result_card_style.border_color = color
	result_title.text = "VAULT OPENED" if won else "ALARM TRIGGERED"
	result_title.add_theme_color_override("font_color", color)
	if won:
		result_flavor.text = ["Clean job — not a single strike.", "Smooth work. Only one slip.", "Phew… that was way too close!"][mini(strikes, 2)]
	else:
		result_flavor.text = reason
	result_time.text = UI.format_time(mission_time)
	result_strikes.text = "%d / %d" % [strikes, MAX_STRIKES]
	result_strikes.add_theme_color_override("font_color", UI.TEXT if strikes == 0 else UI.BAD)
	result_modules.text = "%d / %d" % [_count_solved(), modules.size()]
	result_modules.add_theme_color_override("font_color", UI.GOOD if won else UI.TEXT)
	if won and new_record:
		result_record.text = "NEW BEST TIME!"
		result_record.add_theme_color_override("font_color", UI.AMBER)
	elif progress.has_record(mission_index):
		result_record.text = "BEST TIME  %s" % UI.format_time(progress.get_record(mission_index)["time"])
		result_record.add_theme_color_override("font_color", UI.MUTED)
	else:
		result_record.text = "NOT CLEARED YET"
		result_record.add_theme_color_override("font_color", UI.MUTED)

	# Buttons: the most useful one goes on top.
	var has_next := won and mission_index + 1 < MissionData.count()
	next_mission_button.visible = has_next
	var rows := [[0.315, 0.425], [0.185, 0.295], [0.055, 0.165]]
	var order := [next_mission_button, retry_button, result_menu_button] if has_next else [retry_button, result_menu_button]
	for i in order.size():
		UI.set_rows(order[i], rows[i][0], rows[i][1])

	vault.set_active(false)
	result_screen.visible = true
	_fade_in(result_screen)


# =============================================================================
# Pause
# =============================================================================
func pause_game() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED # stops the timer and blocks the modules
	vault.cancel_touch()
	vault.interactive = false
	vault.set_vault_hidden(true) # no studying the modules while the clock is stopped
	vault.set_active(false)
	pause_caption.text = "MISSION %d  •  %s" % [mission_index + 1, mission["subtitle"]]
	if active_module != null:
		pause_info.text = "%s  %s LEFT   •   STRIKES %d / %d" % [active_module.display_name(), UI.format_time(side_time_left), strikes, MAX_STRIKES]
	else:
		pause_info.text = "NO SIDE OPEN   •   STRIKES %d / %d" % [strikes, MAX_STRIKES]
	pause_screen.visible = true
	_fade_in(pause_screen)
	sfx.play("click")


func resume_game() -> void:
	if state != State.PAUSED:
		return
	pause_screen.visible = false
	settings_screen.visible = false
	vault.set_vault_hidden(false)
	vault.set_active(true)
	vault.interactive = true
	state = State.PLAYING
	sfx.play("click")


## Android back button: closes the top screen, pauses, or leaves the game.
func _on_back_button() -> void:
	if howto_screen.visible:
		close_howto()
	elif settings_screen.visible:
		close_settings()
	elif state == State.PLAYING:
		pause_game()
	elif state == State.PAUSED:
		resume_game()
	elif state == State.RESULT:
		if result_screen.visible:
			show_menu()
	else:
		get_tree().quit()


# =============================================================================
# Settings
# =============================================================================
func _apply_settings() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), not settings.sound)
	vault.rotate_speed = settings.rotate_speed()
	_refresh_settings_ui()


func open_settings() -> void:
	reset_armed = false
	if reset_records_button != null:
		reset_records_button.text = "RESET"
		UI.restyle_button(reset_records_button, UI.PANEL_LIGHT, UI.TEXT, 18)
	_refresh_settings_ui()
	settings_screen.visible = true
	_fade_in(settings_screen)
	sfx.play("click")


func close_settings() -> void:
	settings_screen.visible = false
	settings.save_settings()
	sfx.play("click")


func _toggle_sound() -> void:
	settings.sound = not settings.sound
	_apply_settings()
	sfx.play("good") # heard only when the sound was just turned on


func _toggle_vibration() -> void:
	settings.vibration = not settings.vibration
	_apply_settings()
	if settings.vibration:
		Input.vibrate_handheld(80) # a short buzz shows it works
	sfx.play("click")


func _set_spin_speed(index: int) -> void:
	settings.spin_speed = index
	_apply_settings()
	sfx.play("click")


func _toggle_perf_monitor() -> void:
	settings.perf_monitor = not settings.perf_monitor
	perf.visible = settings.perf_monitor and state != State.MENU
	_apply_settings()
	sfx.play("click")


## Two taps: RESET -> SURE? -> records deleted.
func _reset_records_pressed() -> void:
	sfx.play("click")
	if not reset_armed:
		reset_armed = true
		reset_records_button.text = "SURE?"
		UI.restyle_button(reset_records_button, UI.BAD, UI.DARK, 18)
		return
	progress.reset()
	_refresh_mission_records()
	reset_armed = false
	reset_records_button.text = "CLEARED"
	UI.restyle_button(reset_records_button, UI.SOCKET, UI.TEXT, 18)


func _refresh_settings_ui() -> void:
	if sound_toggle == null:
		return
	_style_toggle(sound_toggle, settings.sound)
	_style_toggle(vibration_toggle, settings.vibration)
	_style_toggle(perf_toggle, settings.perf_monitor)
	for i in spin_buttons.size():
		var selected: bool = i == settings.spin_speed
		UI.restyle_button(spin_buttons[i], UI.AMBER if selected else UI.PANEL_LIGHT, UI.DARK if selected else UI.TEXT, 18)


func _style_toggle(b: Button, on: bool) -> void:
	b.text = "ON" if on else "OFF"
	UI.restyle_button(b, UI.GOOD if on else UI.SOCKET, UI.DARK if on else UI.TEXT, 18)


# =============================================================================
# How to play
# =============================================================================
func open_howto() -> void:
	_show_howto_page(0)
	howto_screen.visible = true
	_fade_in(howto_screen)


func close_howto() -> void:
	howto_screen.visible = false
	settings.tutorial_seen = true
	settings.save_settings()
	sfx.play("click")


func _show_howto_page(index: int) -> void:
	howto_page = clampi(index, 0, howto_pages.size() - 1)
	for i in howto_pages.size():
		(howto_pages[i] as Control).visible = i == howto_page
		(howto_dots[i] as StyleBoxFlat).bg_color = UI.AMBER if i == howto_page else UI.SOCKET
	howto_back.visible = howto_page > 0
	howto_next.text = "GOT IT" if howto_page == howto_pages.size() - 1 else "NEXT"


func _howto_next_pressed() -> void:
	sfx.play("click")
	if howto_page == howto_pages.size() - 1:
		close_howto()
	else:
		_show_howto_page(howto_page + 1)


func _count_solved() -> int:
	var n := 0
	for m in modules:
		if m.is_solved:
			n += 1
	return n


## Short message at the bottom of the game screen. It fades after a few seconds.
func show_status(message: String, color: Color, seconds := STATUS_TIME) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", color if color != UI.MUTED else UI.TEXT)
	status_style.border_color = color if color != UI.MUTED else UI.AMBER
	status_time = seconds
	status_box.modulate.a = 1.0


func _update_status_fade(delta: float) -> void:
	if status_box == null or status_time <= 0.0:
		return
	if state == State.PLAYING:
		status_time -= delta
	status_box.modulate.a = clampf(status_time / 0.6, 0.0, 1.0)


## Menu cards: best time of every mission.
func _refresh_mission_records() -> void:
	for i in mission_records.size():
		var time_label: Label = mission_records[i][0]
		var caption: Label = mission_records[i][1]
		if progress.has_record(i):
			var r := progress.get_record(i)
			time_label.text = UI.format_time(r["time"])
			time_label.add_theme_color_override("font_color", UI.AMBER)
			caption.text = "BEST TIME"
		else:
			time_label.text = ""
			caption.text = "NOT CLEARED"


## HUD + front display: the timer of the open side, or --:-- when no side is open.
func _update_timer_labels() -> void:
	var text := "--:--"
	var color := UI.MUTED
	var shown := true
	if active_module != null:
		text = UI.format_time(side_time_left)
		color = UI.AMBER
		if side_time_left <= 20.0:
			color = UI.BAD
			if side_time_left <= 10.0:
				# blink + tick every second in the last 10 seconds
				shown = fmod(side_time_left, 1.0) > 0.3 or not is_playing()
				var whole := int(ceil(side_time_left))
				if whole != last_whole_second and is_playing():
					sfx.play("tick")
				last_whole_second = whole

	for ghost in [hud_ghost, display_ghost]:
		if ghost != null:
			ghost.visible = active_module != null
	for label in [timer_label, display_timer_label]:
		if label == null:
			continue
		label.text = text
		label.add_theme_color_override("font_color", color)
		label.visible = shown


func _flash(color: Color, alpha: float) -> void:
	flash_color = color
	flash_alpha = alpha


func _update_flash(delta: float) -> void:
	if flash_rect == null:
		return
	flash_alpha = move_toward(flash_alpha, 0.0, delta * 0.9)
	var c := flash_color
	c.a = flash_alpha
	flash_rect.color = c


func _fade_in(c: Control) -> void:
	c.modulate.a = 0.0
	c.create_tween().tween_property(c, "modulate:a", 1.0, 0.25)


# =============================================================================
# Panels on the sides of the vault
# =============================================================================

## FRONT: the vault's main display with the big timer and the strike lights.
func _build_display_face() -> void:
	var t := vault.face_holder(Vault3D.Face.FRONT)
	var band := UI.panel(t, "TitleBand", Color(0, 0, 0, 0.35), 0.08, 0.86, 0.92, 0.97, 16)
	UI.caps(band, "Title", "VAULT CONTROL", 52, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, 8)
	var screen := UI.panel(t, "TimerScreen", UI.DARK, 0.06, 0.44, 0.94, 0.82, 24, UI.AMBER_DIM, 6)
	# Dim "88:88" behind the digits: looks like a real segment display.
	display_ghost = UI.text(screen, "Ghost", "88:88", 250, Color(UI.AMBER, 0.07), HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, true)
	display_timer_label = UI.text(screen, "Timer", "00:00", 250, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, true)
	UI.caps(t, "StrikesCaption", "STRIKES", 40, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.33, 0.96, 0.40, 8)
	display_strike_lights.clear()
	for i in MAX_STRIKES:
		var x := 0.22 + i * 0.2
		display_strike_lights.append(UI.led(t, "StrikeLight%d" % (i + 1), x, 0.14, x + 0.16, 0.31, 12))
	UI.caps(t, "Mission", "%s  •  %s" % [mission["title"], mission["subtitle"]], 34, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.03, 0.96, 0.10, 4)


## TOP: the Vault ID plate (players have to turn the vault to find it).
func _build_plate_face() -> void:
	var t := vault.face_holder(Vault3D.Face.TOP)
	UI.caps(t, "Hint", "SERIAL PLATE", 40, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.80, 0.96, 0.92, 8)
	var plate := UI.panel(t, "Plate", UI.KEY_FACE, 0.07, 0.28, 0.93, 0.74, 22, Color(0.55, 0.52, 0.45), 8)
	UI.caps(plate, "Caption", "VAULT ID", 52, Color(0.25, 0.24, 0.22), HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.68, 0.96, 0.92, 12)
	UI.rect(plate, "Line", Color(0.25, 0.24, 0.22, 0.4), 0.12, 0.655, 0.88, 0.665)
	UI.text(plate, "Code", vault_id.code, 170, UI.DARK, HORIZONTAL_ALIGNMENT_CENTER, 0.02, 0.06, 0.98, 0.64, true)
	for corner in [[0.10, 0.65], [0.86, 0.65], [0.10, 0.33], [0.86, 0.33]]:
		var rivet := UI.circle(t, "Rivet", UI.SOCKET, corner[0], corner[1], corner[0] + 0.04, corner[1] + 0.04)
		rivet.set_border_width_all(4)
		rivet.border_color = Color(0, 0, 0, 0.4)
	UI.text(t, "Note", "Read it to your Expert", 34, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.10, 0.96, 0.20)


## A side without a module (Mission 1 has only two modules).
func _build_empty_face(face: int) -> void:
	var t := vault.face_holder(face)
	for i in 6:
		var y := 0.22 + i * 0.1
		UI.panel(t, "Vent%d" % i, UI.DARK, 0.15, y, 0.85, y + 0.05, 4096)
	UI.caps(t, "Text", "EMPTY SLOT", 48, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.84, 0.96, 0.96, 10)


# =============================================================================
# UI building
# =============================================================================
func _build_ui() -> void:
	# Full-screen background (also behind the notch).
	UI.rect(self, "Background", UI.BACKGROUND, 0, 0, 1, 1)

	safe_root = UI.area(self, "SafeArea", 0, 0, 1, 1)

	_build_vault_view() # 3D vault behind everything (menu + game)
	UI.vignette(safe_root, "Vignette")
	_build_menu_screen()
	_build_game_screen()
	_build_result_screen()
	_build_pause_screen()
	_build_settings_screen()
	_build_howto_screen() # on top of everything

	# Performance overlay (Settings -> PERF MONITOR), just under the HUD bar.
	perf = PerfMonitor.new()
	perf.name = "PerfMonitor"
	perf.game = self
	perf.vault = vault
	UI.place(safe_root, perf, 0.02, 0.808, 0.98, 0.898)
	perf.visible = false

	flash_rect = UI.rect(self, "FlashOverlay", Color(1, 0, 0, 0), 0, 0, 1, 1)


func _build_vault_view() -> void:
	var container := SubViewportContainer.new()
	container.name = "VaultView"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	UI.place(safe_root, container, 0, 0, 1, 1)
	var view := SubViewport.new()
	view.name = "VaultViewport"
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_2X
	view.handle_input_locally = true
	container.add_child(view)
	vault = Vault3D.new()
	vault.name = "Vault3D"
	view.add_child(vault)


func _build_menu_screen() -> void:
	menu_screen = UI.area(safe_root, "MenuScreen", 0, 0, 1, 1)
	var t := menu_screen

	# --- Logo ---
	UI.caps(t, "Tagline", "CO-OP HEIST PUZZLE  •  2 PLAYERS", 28, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.03, 0.945, 0.97, 0.975, 5)
	UI.text(t, "Title", "VAULT", 170, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 0.03, 0.855, 0.97, 0.945, true)
	UI.caps(t, "Title2", "PROTOCOL", 74, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0.03, 0.815, 0.97, 0.86, 26)

	# (the 3D vault spins here, between the logo and the buttons)

	# --- Help + settings ---
	UI.button(t, "HowToButton", "HOW TO PLAY", 32, UI.PANEL_LIGHT, UI.TEXT, 0.05, 0.437, 0.49, 0.497, open_howto, 20)
	UI.button(t, "SettingsButton", "SETTINGS", 32, UI.PANEL_LIGHT, UI.TEXT, 0.51, 0.437, 0.95, 0.497, open_settings, 20)

	# --- Missions ---
	for i in MissionData.count():
		var y_max := 0.415 - i * 0.112
		_mission_card(t, i, y_max - 0.1, y_max)

	var version := str(ProjectSettings.get_setting("application/config/version", "0.4"))
	UI.caps(t, "Footer", "VERSION %s   •   MANUAL REV. 1.3   •   MT-2401" % version, 22, Color(UI.MUTED, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 0.03, 0.012, 0.97, 0.045, 3)


func _mission_card(parent: Control, index: int, y_min: float, y_max: float) -> void:
	var m := MissionData.get_mission(index)
	var b := Button.new()
	b.name = "Mission%dButton" % (index + 1)
	b.focus_mode = Control.FOCUS_NONE
	var normal := UI.flat_style(UI.PANEL_LIGHT, 24)
	normal.border_width_left = 14
	normal.border_color = UI.AMBER
	normal.shadow_color = Color(0, 0, 0, 0.35)
	normal.shadow_size = 10
	normal.shadow_offset = Vector2(0, 6)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = UI.PANEL_LIGHT.darkened(0.25)
	pressed.shadow_size = 2
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UI.place(parent, b, 0.05, y_min, 0.95, y_max)
	b.pressed.connect(start_mission.bind(index))

	UI.text(b, "Number", "%02d" % (index + 1), 92, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0.03, 0.05, 0.21, 0.95, true)
	UI.rect(b, "Divider", UI.LINE, 0.215, 0.18, 0.218, 0.82)
	UI.text(b, "Title", m["subtitle"], 46, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 0.25, 0.48, 0.74, 0.92, true)
	var names := ["WIRES", "BUTTON"]
	if m["has_keypad"]:
		names.append("KEYPAD")
	if m["has_word_lock"]:
		names.append("WORDS")
	var modules_text := "  •  ".join(PackedStringArray(names))
	UI.caps(b, "Modules", modules_text, 24, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, 0.25, 0.12, 0.74, 0.46, 3)
	# best time (saved on the phone)
	var best := UI.text(b, "Best", "--:--", 50, UI.SOCKET, HORIZONTAL_ALIGNMENT_RIGHT, 0.70, 0.46, 0.95, 0.92, true)
	var best_caption := UI.caps(b, "BestCaption", "NOT CLEARED", 20, UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 0.66, 0.14, 0.95, 0.44, 3)
	mission_records.append([best, best_caption])


func _build_game_screen() -> void:
	game_screen = UI.area(safe_root, "GameScreen", 0, 0, 1, 1)
	var t := game_screen

	# --- HUD top: menu button, timer, strikes ---
	var header := UI.panel(t, "Header", Color(UI.PANEL_DARK, 0.94), 0, 0.905, 1, 1, 0)
	var header_style: StyleBoxFlat = header.get_meta("style")
	header_style.border_width_bottom = 4
	header_style.border_color = UI.AMBER_DIM
	var pause_button := UI.button(t, "PauseButton", "", 10, UI.PANEL_LIGHT, UI.TEXT, 0.03, 0.918, 0.20, 0.988, pause_game, 18)
	UI.rect(pause_button, "BarLeft", UI.TEXT, 0.33, 0.30, 0.44, 0.76) # the pause sign
	UI.rect(pause_button, "BarRight", UI.TEXT, 0.56, 0.30, 0.67, 0.76)
	var timer_box := UI.panel(t, "TimerBox", UI.DARK, 0.255, 0.915, 0.615, 0.99, 18, UI.AMBER_DIM, 3)
	hud_ghost = UI.text(timer_box, "Ghost", "88:88", 84, Color(UI.AMBER, 0.07), HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, true)
	timer_label = UI.text(timer_box, "Timer", "00:00", 84, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, true)
	var strike_block := UI.area(t, "Strikes", 0.645, 0.92, 0.975, 0.985)
	for i in MAX_STRIKES:
		var x := float(i) / MAX_STRIKES
		strike_lights.append(UI.led(strike_block, "StrikeLight%d" % (i + 1), x + 0.05, 0.10, x + 1.0 / MAX_STRIKES - 0.05, 0.90, 5))

	# --- HUD bottom: one short message that fades after a few seconds ---
	# (v0.4: the mission/progress row, the OPERATOR LOG caption and the hint
	# line were removed to keep the screen simple; the vault itself shows the
	# mission name, and every sealed side says TAP TO OPEN.)
	var box := UI.panel(t, "StatusBox", Color(UI.PANEL_DARK, 0.94), 0.04, 0.03, 0.96, 0.105, 22, UI.LINE, 2)
	status_box = box
	status_style = box.get_meta("style")
	status_style.border_color = UI.AMBER
	status_style.set_border_width_all(3)
	status_label = UI.text(box, "Status", "", 34, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.06, 0.96, 0.94, true)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _build_result_screen() -> void:
	result_screen = UI.rect(safe_root, "ResultScreen", Color(0.02, 0.03, 0.04, 0.80), 0, 0, 1, 1, true) # blocks touches
	var card := UI.panel(result_screen, "Card", UI.PANEL, 0.05, 0.20, 0.95, 0.80, 32, UI.GOOD, 4)
	result_card_style = card.get_meta("style")
	result_card_style.shadow_color = Color(0, 0, 0, 0.5)
	result_card_style.shadow_size = 24

	result_caption = UI.caps(card, "Caption", "", 26, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.90, 0.96, 0.96, 4)
	result_title = UI.text(card, "Title", "", 84, UI.GOOD, HORIZONTAL_ALIGNMENT_CENTER, 0.03, 0.79, 0.97, 0.90, true)
	result_flavor = UI.text(card, "Flavor", "", 36, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 0.06, 0.70, 0.94, 0.79)

	# Three stat boxes
	var stats := [["TIME", "Time"], ["STRIKES", "Strikes"], ["SIDES", "Modules"]]
	var value_labels := []
	for i in 3:
		var x := 0.05 + i * 0.31
		var box := UI.panel(card, stats[i][1] + "Box", UI.PANEL_DARK, x, 0.50, x + 0.28, 0.68, 20, UI.LINE, 2)
		value_labels.append(UI.text(box, "Value", "", 58, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 0.02, 0.32, 0.98, 0.95, true))
		UI.caps(box, "Caption", stats[i][0], 20, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.02, 0.06, 0.98, 0.32, 3)
	result_time = value_labels[0]
	result_time.add_theme_color_override("font_color", UI.AMBER)
	result_strikes = value_labels[1]
	result_modules = value_labels[2]
	result_record = UI.caps(card, "Record", "", 30, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.435, 0.96, 0.485, 4)

	retry_button = UI.button(card, "RetryButton", "RETRY", 46, UI.AMBER, UI.DARK, 0.07, 0.315, 0.93, 0.425, func(): start_mission(mission_index))
	next_mission_button = UI.button(card, "NextMissionButton", "NEXT MISSION", 46, UI.GOOD, UI.DARK, 0.07, 0.185, 0.93, 0.295, func(): start_mission(mission_index + 1))
	result_menu_button = UI.button(card, "MenuButton", "MAIN MENU", 46, UI.PANEL_LIGHT, UI.TEXT, 0.07, 0.055, 0.93, 0.165, show_menu)


func _build_pause_screen() -> void:
	pause_screen = UI.rect(safe_root, "PauseScreen", Color(0.02, 0.03, 0.04, 0.90), 0, 0, 1, 1, true) # blocks touches
	var card := UI.panel(pause_screen, "Card", UI.PANEL, 0.05, 0.20, 0.95, 0.80, 32, UI.AMBER_DIM, 3)
	var card_style: StyleBoxFlat = card.get_meta("style")
	card_style.shadow_color = Color(0, 0, 0, 0.5)
	card_style.shadow_size = 24
	pause_caption = UI.caps(card, "Caption", "", 26, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.90, 0.96, 0.96, 4)
	UI.text(card, "Title", "PAUSED", 100, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 0.03, 0.77, 0.97, 0.90, true)
	pause_info = UI.caps(card, "Info", "", 30, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.70, 0.96, 0.765, 3)
	UI.text(card, "Note", "The timer is stopped and the vault is hidden.", 30, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.06, 0.62, 0.94, 0.69)
	UI.button(card, "ResumeButton", "RESUME", 46, UI.GOOD, UI.DARK, 0.07, 0.465, 0.93, 0.575, resume_game)
	UI.button(card, "RestartButton", "RESTART", 46, UI.AMBER, UI.DARK, 0.07, 0.335, 0.93, 0.445, func(): start_mission(mission_index))
	UI.button(card, "SettingsButton", "SETTINGS", 40, UI.PANEL_LIGHT, UI.TEXT, 0.07, 0.205, 0.93, 0.315, open_settings)
	UI.button(card, "MenuButton", "MAIN MENU", 40, UI.PANEL_LIGHT, UI.TEXT, 0.07, 0.075, 0.93, 0.185, show_menu)
	pause_screen.visible = false


func _build_settings_screen() -> void:
	settings_screen = UI.rect(safe_root, "SettingsScreen", Color(0.02, 0.03, 0.04, 0.88), 0, 0, 1, 1, true)
	var card := UI.panel(settings_screen, "Card", UI.PANEL, 0.05, 0.14, 0.95, 0.86, 32, UI.AMBER_DIM, 3)
	UI.caps(card, "Caption", "VAULT PROTOCOL", 24, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.925, 0.96, 0.965, 6)
	UI.text(card, "Title", "SETTINGS", 80, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.835, 0.96, 0.925, true)
	sound_toggle = _settings_row(card, "SOUND", "Beeps, ticks and the alarm", 0.72, 0.81, _toggle_sound)
	vibration_toggle = _settings_row(card, "VIBRATION", "The phone buzzes on a strike", 0.60, 0.69, _toggle_vibration)
	UI.caps(card, "SpinTitle", "SPIN SPEED", 32, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 0.07, 0.535, 0.65, 0.575, 4)
	UI.text(card, "SpinNote", "How fast the vault turns under your finger", 26, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, 0.07, 0.50, 0.95, 0.535)
	spin_buttons.clear()
	for i in GameSettings.SPIN_NAMES.size():
		var x := 0.07 + i * 0.29
		spin_buttons.append(UI.button(card, "Spin%d" % i, GameSettings.SPIN_NAMES[i], 30, UI.PANEL_LIGHT, UI.TEXT, x, 0.405, x + 0.27, 0.48, _set_spin_speed.bind(i), 18))
	UI.rect(card, "SpinLine", UI.LINE, 0.07, 0.383, 0.93, 0.386)
	perf_toggle = _settings_row(card, "PERF MONITOR", "FPS and frame time on screen (for tests)", 0.27, 0.36, _toggle_perf_monitor)
	reset_records_button = _settings_row(card, "RECORDS", "Delete the saved best times", 0.15, 0.24, _reset_records_pressed)
	reset_records_button.text = "RESET"
	UI.restyle_button(reset_records_button, UI.PANEL_LIGHT, UI.TEXT, 18)
	UI.button(card, "DoneButton", "DONE", 46, UI.AMBER, UI.DARK, 0.07, 0.03, 0.93, 0.115, close_settings)
	settings_screen.visible = false


func _settings_row(card: Control, title: String, note: String, y_min: float, y_max: float, on_pressed: Callable) -> Button:
	UI.rect(card, title + "Line", UI.LINE, 0.07, y_max + 0.008, 0.93, y_max + 0.011)
	var row := UI.area(card, title + "Row", 0.07, y_min, 0.93, y_max)
	UI.caps(row, "Title", title, 32, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 0, 0.5, 0.65, 1, 4)
	UI.text(row, "Note", note, 26, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, 0, 0, 0.68, 0.5)
	return UI.button(row, "Toggle", "ON", 34, UI.GOOD, UI.DARK, 0.70, 0.12, 1.0, 0.88, on_pressed, 18)


func _build_howto_screen() -> void:
	howto_screen = UI.rect(safe_root, "HowToScreen", UI.BACKGROUND, 0, 0, 1, 1, true)
	var t := howto_screen
	UI.caps(t, "Caption", "HOW TO PLAY", 28, UI.AMBER, HORIZONTAL_ALIGNMENT_LEFT, 0.06, 0.932, 0.6, 0.972, 6)
	UI.button(t, "SkipButton", "SKIP", 28, UI.PANEL_LIGHT, UI.TEXT, 0.74, 0.928, 0.95, 0.976, close_howto, 16)
	var area := UI.area(t, "Pages", 0.05, 0.165, 0.95, 0.915)
	howto_pages = [_howto_roles(area), _howto_controls(area), _howto_rules(area)]
	howto_dots.clear()
	for i in howto_pages.size():
		var x := 0.445 + i * 0.045
		var dot := UI.circle(t, "Dot%d" % i, UI.SOCKET, x, 0.125, x + 0.025, 0.142)
		dot.set_border_width_all(0)
		howto_dots.append(dot)
	howto_back = UI.button(t, "BackButton", "BACK", 40, UI.PANEL_LIGHT, UI.TEXT, 0.05, 0.03, 0.36, 0.105, func(): _show_howto_page(howto_page - 1), 20)
	howto_next = UI.button(t, "NextButton", "NEXT", 40, UI.AMBER, UI.DARK, 0.40, 0.03, 0.95, 0.105, _howto_next_pressed, 20)
	howto_screen.visible = false


## Page 1: the two roles.
func _howto_roles(area: Control) -> Control:
	var p := UI.area(area, "Roles", 0, 0, 1, 1)
	UI.text(p, "Title", "TWO PLAYERS,\nONE VAULT", 66, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 0.01, 0.84, 0.99, 1.0, true)
	var op := _role_block(p, "1", "OPERATOR", "Holds this phone. Turns the vault, describes what is on every side and does what the Expert says.", 0.47, 0.81)
	var phone := UI.panel(op, "Phone", UI.DARK, 0.775, 0.13, 0.935, 0.87, 22, UI.TEXT, 6)
	var screen := UI.panel(phone, "Screen", UI.PANEL_LIGHT, 0.14, 0.12, 0.86, 0.88, 8)
	UI.panel(screen, "Vault", UI.CLEAR, 0.22, 0.36, 0.78, 0.64, 6, UI.AMBER, 6)
	var ex := _role_block(p, "2", "EXPERT", "Opens the PDF manual on another device, finds the right rule and tells the Operator what to do.", 0.12, 0.46)
	var page := UI.panel(ex, "Manual", UI.KEY_FACE, 0.765, 0.13, 0.945, 0.87, 6)
	for i in 6:
		var y := 0.72 - i * 0.11
		UI.rect(page, "Line%d" % i, Color(0.25, 0.24, 0.22), 0.14, y, 0.86 - (i % 3) * 0.12, y + 0.04)
	UI.text(p, "Note", "No peeking at each other's screens — you can only talk!", 30, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0.01, 0.0, 0.99, 0.10)
	return p


func _role_block(p: Control, number: String, title: String, body: String, y_min: float, y_max: float) -> Panel:
	var card := UI.panel(p, title + "Card", UI.PANEL, 0, y_min, 1, y_max, 26, UI.LINE, 2)
	var badge := UI.circle(card, "Badge", UI.AMBER, 0.05, 0.63, 0.16, 0.90)
	badge.set_border_width_all(0)
	UI.text(card, "Number", number, 44, UI.DARK, HORIZONTAL_ALIGNMENT_CENTER, 0.05, 0.63, 0.16, 0.90, true)
	UI.caps(card, "Title", title, 40, UI.AMBER, HORIZONTAL_ALIGNMENT_LEFT, 0.20, 0.63, 0.72, 0.90, 5)
	UI.text(card, "Body", body, 31, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 0.05, 0.06, 0.72, 0.60)
	return card


## Page 2: the touch controls.
func _howto_controls(area: Control) -> Control:
	var p := UI.area(area, "Controls", 0, 0, 1, 1)
	UI.text(p, "Title", "TOUCH\nCONTROLS", 66, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 0.01, 0.84, 0.99, 1.0, true)
	var rows := [
		["DRAG", "Turn the vault. It locks while a side is open."],
		["TAP", "Open a side. Cut a wire, press a key or a word."],
		["HOLD", "Keep pressing the big button. Let go on the right number."],
		["PINCH", "Two fingers zoom in and out."],
		["PAUSE", "The pause button is at the top left. The vault hides while paused."],
	]
	for i in rows.size():
		var y_max := 0.81 - i * 0.16
		var row := UI.panel(p, "Row%d" % i, UI.PANEL, 0, y_max - 0.14, 1, y_max, 20, UI.LINE, 2)
		var chip := UI.panel(row, "Chip", UI.AMBER, 0.03, 0.22, 0.24, 0.78, 4096)
		UI.caps(chip, "Text", rows[i][0], 28, UI.DARK, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, 3)
		UI.text(row, "Text", rows[i][1], 30, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 0.28, 0.05, 0.97, 0.95)
	p.visible = false
	return p


## Page 3: the rules.
func _howto_rules(area: Control) -> Control:
	var p := UI.area(area, "Rules", 0, 0, 1, 1)
	UI.text(p, "Title", "DISARM\nTHE VAULT", 66, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 0.01, 0.84, 0.99, 1.0, true)
	var rules := [
		[UI.AMBER, "Every side has its own timer. Tap a side to open it: the vault locks until it is disarmed."],
		[UI.BAD, "A side timer at 00:00 or three STRIKES set off the alarm."],
		[UI.TEXT, "Read the VAULT ID on top BEFORE you open a side. Spell words: STEEL is not STEAL!"],
		[UI.GOOD, "Status lights: red = sealed, amber = open, green = disarmed."],
		[UI.AMBER, "Your best time for every mission is saved on the phone."],
	]
	for i in rules.size():
		var y_max := 0.81 - i * 0.16
		var row := UI.panel(p, "Rule%d" % i, UI.PANEL, 0, y_max - 0.145, 1, y_max, 20, UI.LINE, 2)
		var light := UI.led(row, "Light", 0.03, 0.25, 0.12, 0.75, 5)
		UI.set_light(light, rules[i][0])
		UI.text(row, "Text", rules[i][1], 31, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 0.16, 0.05, 0.97, 0.95)
	p.visible = false
	return p


## Keeps the UI inside the phone's safe area (notch) and, on wide screens
## (tablet, desktop window), keeps a phone-shaped column in the middle.
func _apply_layout() -> void:
	var vp := get_viewport_rect().size
	var left := 0.0
	var top := 0.0
	var right := 0.0
	var bottom := 0.0

	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var screen := DisplayServer.screen_get_size()
		if screen.x > 0 and screen.y > 0:
			var sx := vp.x / screen.x
			var sy := vp.y / screen.y
			left = safe.position.x * sx
			top = safe.position.y * sy
			right = (screen.x - safe.end.x) * sx
			bottom = (screen.y - safe.end.y) * sy

	var available_width := vp.x - left - right
	var max_width := (vp.y - top - bottom) * 0.6
	if available_width > max_width:
		var extra := (available_width - max_width) * 0.5
		left += extra
		right += extra

	safe_root.offset_left = left
	safe_root.offset_top = top
	safe_root.offset_right = -right
	safe_root.offset_bottom = -bottom
