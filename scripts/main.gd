# main.gd  (the GameManager)
# -----------------------------------------------------------------------------
# The "brain" of Vault Protocol. Attached to the root node of main.tscn.
#   * builds the UI (menu, HUD, result screen) and the 3D vault from code,
#   * runs the game states: MENU -> PLAYING -> RESULT -> (Retry / Next / Menu),
#   * counts down the timer and counts strikes (3 strikes = alarm = lose),
#   * puts the modules of the selected mission on the sides of the vault.
#
# Sides of the vault:  FRONT = timer display,  RIGHT = Wires,  BACK = Button,
#                      LEFT = Keypad (Mission 2),  TOP = Vault ID plate.
# In the menu the same vault slowly spins behind the title (showcase mode).
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

enum State { MENU, PLAYING, RESULT }

const MAX_STRIKES := 3
const RESULT_DELAY := 0.9 # pause so players see their last action

var state: State = State.MENU
var sfx: Node

# ---- mission state ----
var rng := RandomNumberGenerator.new()
var mission_index := 0
var mission: Dictionary
var vault_id: VaultId
var time_left := 0.0
var strikes := 0
var last_whole_second := -1
var modules: Array = []
var module_faces: Array = [] # which vault side each module is on
var flow_token := 0 # changes on every restart/menu, cancels pending result screens

# ---- UI references ----
var safe_root: Control
var menu_screen: Control
var game_screen: Control
var result_screen: Control
var vault: Vault3D # the 3D vault (vault_3d.gd)
var mission_label: Label
var disarmed_label: Label
var timer_label: Label # small timer in the HUD
var display_timer_label: Label # big timer on the front of the vault
var status_label: Label
var status_style: StyleBoxFlat
var strike_lights: Array = [] # HUD
var display_strike_lights: Array = [] # front of the vault
var result_card_style: StyleBoxFlat
var result_caption: Label
var result_title: Label
var result_flavor: Label
var result_time: Label
var result_strikes: Label
var result_modules: Label
var retry_button: Button
var next_mission_button: Button
var result_menu_button: Button
var flash_rect: ColorRect
var flash_alpha := 0.0
var flash_color := Color.RED


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
	sfx = SoundFx.new()
	sfx.name = "SoundFx"
	add_child(sfx)

	_build_ui()
	get_viewport().size_changed.connect(_apply_layout)
	_apply_layout()
	show_menu()


func _process(delta: float) -> void:
	_update_flash(delta)

	if state != State.PLAYING:
		return

	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_update_timer_labels()
		_end_mission(false, "Time is up!")
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
	_clear_mission()
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
	time_left = mission["time_limit"]
	strikes = 0
	last_whole_second = -1

	mission_label.text = "MISSION %d  •  %s" % [index + 1, mission["subtitle"]]
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
	_update_disarmed_label()

	show_status("Find the VAULT ID on top of the vault and read it to your Expert.", UI.MUTED)

	menu_screen.visible = false
	result_screen.visible = false
	game_screen.visible = true
	_fade_in(game_screen)
	vault.set_showcase(false)
	vault.reset_view()
	vault.set_active(true)
	vault.interactive = true
	state = State.PLAYING
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
	modules.append(module)
	module_faces.append(face)
	vault.set_led(face, true, UI.BAD)


func _clear_mission() -> void:
	modules.clear()
	module_faces.clear()
	display_timer_label = null
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
	_build_plate_face()
	var demo := [[WiresModule, Vault3D.Face.RIGHT], [ButtonModule, Vault3D.Face.BACK], [KeypadModule, Vault3D.Face.LEFT]]
	for d in demo:
		var module: Control = (d[0] as GDScript).new()
		UI.place(vault.face_holder(d[1]), module, 0, 0, 1, 1)
		module.init_module(self, mission, vault_id, demo_rng)
		vault.set_led(d[1], true, UI.BAD)


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
	sfx.play("solved")
	_flash(UI.GOOD, 0.25)
	vault.pop()
	show_status(message, UI.GOOD)
	_update_disarmed_label()

	if _count_solved() == modules.size():
		_end_mission(true, "")


func _end_mission(won: bool, reason: String) -> void:
	state = State.RESULT # stops the timer and blocks all modules
	vault.interactive = false
	timer_label.visible = true # never end on a "blink off" frame
	if display_timer_label != null:
		display_timer_label.visible = true
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
	result_time.text = UI.format_time(time_left)
	result_strikes.text = "%d / %d" % [strikes, MAX_STRIKES]
	result_strikes.add_theme_color_override("font_color", UI.TEXT if strikes == 0 else UI.BAD)
	result_modules.text = "%d / %d" % [_count_solved(), modules.size()]
	result_modules.add_theme_color_override("font_color", UI.GOOD if won else UI.TEXT)

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


func _count_solved() -> int:
	var n := 0
	for m in modules:
		if m.is_solved:
			n += 1
	return n


func _update_disarmed_label() -> void:
	var solved := _count_solved()
	disarmed_label.text = "DISARMED %d / %d" % [solved, modules.size()]
	disarmed_label.add_theme_color_override("font_color", UI.GOOD if solved > 0 else UI.MUTED)


func show_status(message: String, color: Color) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", color if color != UI.MUTED else UI.TEXT)
	status_style.border_color = color if color != UI.MUTED else UI.AMBER


func _update_timer_labels() -> void:
	var text := UI.format_time(time_left)
	var color := UI.AMBER
	var shown := true
	if time_left <= 30.0:
		color = UI.BAD
		if time_left <= 10.0:
			# blink + tick every second in the last 10 seconds
			shown = fmod(time_left, 1.0) > 0.3 or not is_playing()
			var whole := int(ceil(time_left))
			if whole != last_whole_second and is_playing():
				sfx.play("tick")
			last_whole_second = whole

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
	UI.text(screen, "Ghost", "88:88", 250, Color(UI.AMBER, 0.07), HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, true)
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
	var stamp := UI.panel(t, "Stamp", Color(0.6, 0.1, 0.1, 0.15), 0.71, 0.908, 0.985, 0.938, 10, Color(0.9, 0.25, 0.25, 0.85), 4)
	UI.caps(stamp, "Text", "TOP SECRET", 24, Color(1.0, 0.4, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, 4)
	stamp.rotation = deg_to_rad(12.0)

	# (the 3D vault spins here, between the logo and the cards)

	# --- Roles ---
	_role_card(t, "Operator", "1", "OPERATOR", "Holds this phone. Turns the vault and does the actions.", 0.04, 0.485)
	_role_card(t, "Expert", "2", "EXPERT", "Reads the PDF manual on another device.", 0.515, 0.96)
	UI.text(t, "NoPeeking", "Don't look at each other's screens — just talk!", 28, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.03, 0.302, 0.97, 0.332)

	# --- Missions ---
	for i in MissionData.count():
		var y_max := 0.29 - i * 0.12
		_mission_card(t, i, y_max - 0.105, y_max)

	UI.caps(t, "Footer", "MANUAL REV. 1.1   •   MT-2401   •   PROTOTYPE", 22, Color(UI.MUTED, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 0.03, 0.012, 0.97, 0.045, 3)


func _role_card(parent: Control, card_name: String, number: String, title: String, body: String, x_min: float, x_max: float) -> void:
	var card := UI.panel(parent, card_name + "Card", Color(UI.PANEL, 0.88), x_min, 0.34, x_max, 0.47, 22, UI.LINE, 2)
	var badge := UI.circle(card, "Badge", UI.AMBER, 0.06, 0.60, 0.24, 0.92)
	badge.set_border_width_all(0)
	UI.text(card, "Number", number, 38, UI.DARK, HORIZONTAL_ALIGNMENT_CENTER, 0.06, 0.60, 0.24, 0.92, true)
	UI.caps(card, "Title", title, 32, UI.AMBER, HORIZONTAL_ALIGNMENT_LEFT, 0.28, 0.60, 0.97, 0.92, 4)
	UI.text(card, "Body", body, 27, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 0.07, 0.06, 0.95, 0.58)


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
	var modules_text := "WIRES  •  BUTTON  •  KEYPAD" if m["has_keypad"] else "WIRES  •  BUTTON"
	UI.caps(b, "Modules", modules_text, 24, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, 0.25, 0.12, 0.80, 0.46, 3)
	UI.text(b, "Time", UI.format_time(m["time_limit"]), 50, UI.AMBER, HORIZONTAL_ALIGNMENT_RIGHT, 0.72, 0.46, 0.95, 0.92, true)
	# difficulty: 1 or 2 of 3 lights
	for k in 3:
		var x := 0.80 + k * 0.05
		var pip := UI.circle(b, "Pip%d" % k, UI.AMBER if k <= index else UI.SOCKET, x, 0.16, x + 0.035, 0.40)
		pip.set_border_width_all(0)


func _build_game_screen() -> void:
	game_screen = UI.area(safe_root, "GameScreen", 0, 0, 1, 1)
	var t := game_screen

	# --- HUD top: menu button, timer, strikes ---
	var header := UI.panel(t, "Header", Color(UI.PANEL_DARK, 0.94), 0, 0.905, 1, 1, 0)
	var header_style: StyleBoxFlat = header.get_meta("style")
	header_style.border_width_bottom = 4
	header_style.border_color = UI.AMBER_DIM
	UI.button(t, "MenuButton", "MENU", 32, UI.PANEL_LIGHT, UI.TEXT, 0.03, 0.918, 0.22, 0.988, show_menu, 18)
	var timer_box := UI.panel(t, "TimerBox", UI.DARK, 0.255, 0.915, 0.615, 0.99, 18, UI.AMBER_DIM, 3)
	UI.text(timer_box, "Ghost", "88:88", 84, Color(UI.AMBER, 0.07), HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, true)
	timer_label = UI.text(timer_box, "Timer", "00:00", 84, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, true)
	var strike_block := UI.area(t, "Strikes", 0.645, 0.92, 0.975, 0.985)
	for i in MAX_STRIKES:
		var x := float(i) / MAX_STRIKES
		strike_lights.append(UI.led(strike_block, "StrikeLight%d" % (i + 1), x + 0.05, 0.10, x + 1.0 / MAX_STRIKES - 0.05, 0.90, 5))

	# --- Mission name + progress under the header ---
	mission_label = UI.caps(t, "MissionName", "", 24, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, 0.04, 0.872, 0.64, 0.902, 3)
	disarmed_label = UI.caps(t, "Disarmed", "", 24, UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 0.60, 0.872, 0.96, 0.902, 3)

	# --- HUD bottom: status log + hint ---
	var status_box := UI.panel(t, "StatusBox", Color(UI.PANEL_DARK, 0.94), 0.03, 0.072, 0.97, 0.172, 22, UI.LINE, 2)
	status_style = status_box.get_meta("style")
	status_style.border_width_left = 12
	status_style.border_color = UI.AMBER
	UI.caps(status_box, "Caption", "OPERATOR LOG", 20, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, 0.05, 0.70, 0.9, 0.94, 4)
	status_label = UI.text(status_box, "Status", "", 34, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 0.05, 0.05, 0.97, 0.72, true)
	UI.text(t, "Hint", "Drag to turn the vault  •  Tap a module to use it", 28, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.03, 0.015, 0.97, 0.06)


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
	var stats := [["TIME LEFT", "Time"], ["STRIKES", "Strikes"], ["MODULES", "Modules"]]
	var value_labels := []
	for i in 3:
		var x := 0.05 + i * 0.31
		var box := UI.panel(card, stats[i][1] + "Box", UI.PANEL_DARK, x, 0.47, x + 0.28, 0.66, 20, UI.LINE, 2)
		value_labels.append(UI.text(box, "Value", "", 58, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 0.02, 0.32, 0.98, 0.95, true))
		UI.caps(box, "Caption", stats[i][0], 20, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.02, 0.06, 0.98, 0.32, 3)
	result_time = value_labels[0]
	result_time.add_theme_color_override("font_color", UI.AMBER)
	result_strikes = value_labels[1]
	result_modules = value_labels[2]

	retry_button = UI.button(card, "RetryButton", "RETRY", 46, UI.AMBER, UI.DARK, 0.07, 0.315, 0.93, 0.425, func(): start_mission(mission_index))
	next_mission_button = UI.button(card, "NextMissionButton", "NEXT MISSION", 46, UI.GOOD, UI.DARK, 0.07, 0.185, 0.93, 0.295, func(): start_mission(mission_index + 1))
	result_menu_button = UI.button(card, "MenuButton", "MAIN MENU", 46, UI.PANEL_LIGHT, UI.TEXT, 0.07, 0.055, 0.93, 0.165, show_menu)


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
