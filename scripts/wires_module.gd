# wires_module.gd
# -----------------------------------------------------------------------------
# MODULE 1 - WIRES
# 3-5 colored wires, numbered from the top. Tap a wire to cut it.
# Correct wire -> module disarmed. Any other wire -> strike (and it stays cut).
# The correct wire is decided by PuzzleRules.wire_to_cut().
# -----------------------------------------------------------------------------
extends "res://scripts/vault_module.gd"

var colors: Array = []
var is_cut: Array = []
var correct_index := 0

var left_parts: Array = []
var middle_parts: Array = []
var right_parts: Array = []


func display_name() -> String:
	return "WIRES"


func solution_for_debug() -> String:
	return "Wires: cut wire %d" % (correct_index + 1)


func build(mission: Dictionary) -> void:
	# 1) Random puzzle
	var count: int = rng.randi_range(mission["min_wires"], mission["max_wires"])
	for i in count:
		colors.append(rng.randi_range(0, 4)) # one of the 5 WireColor values
		is_cut.append(false)
	correct_index = PuzzleRules.wire_to_cut(colors, vault_id)

	# 2) UI
	create_header("WIRE PANEL  •  %d WIRES" % count, "Tap a wire to cut it")

	# Space for 5 rows; fewer wires are centered vertically.
	var area_top := 0.885
	var area_bottom := 0.105
	var slot := (area_top - area_bottom) / 5.0
	var top := area_top - (5 - count) * slot * 0.5

	for i in count:
		var y_max := top - i * slot
		var y_min := y_max - slot
		var c := UI.wire_color(colors[i])

		# Invisible full-width button = big touch area for the wire.
		var row := UI.touch_area(self, "Wire%d" % (i + 1), 0.03, y_min, 0.97, y_max, _on_wire_tapped.bind(i))

		# Wires are rounded "cables" with a shadow; they go into metal sockets.
		left_parts.append(_cable(row, "WireLeft", c, 0.09, 0.47))
		middle_parts.append(_cable(row, "WireMiddle", c, 0.44, 0.56))
		right_parts.append(_cable(row, "WireRight", c, 0.53, 0.91))

		var socket_left := UI.panel(row, "SocketLeft", UI.SOCKET, 0.0, 0.20, 0.11, 0.80, 14, Color(0, 0, 0, 0.45), 4)
		UI.text(socket_left, "Number", str(i + 1), 46, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, true)
		UI.panel(row, "SocketRight", UI.SOCKET, 0.89, 0.20, 1.0, 0.80, 14, Color(0, 0, 0, 0.45), 4)

		# Small color name: helps color-blind players and avoids arguments.
		UI.text(row, "ColorName", PuzzleRules.WIRE_NAMES[colors[i]], 28, UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 0.55, 0.62, 0.88, 1.0)


func _on_wire_tapped(i: int) -> void:
	if not can_act() or is_cut[i]:
		return

	is_cut[i] = true
	_show_cut(i)

	if i == correct_index:
		solve("Wire %d cut — correct! WIRES disarmed." % (i + 1))
	else:
		strike("Wire %d was the WRONG wire!" % (i + 1))


func _show_cut(i: int) -> void:
	middle_parts[i].visible = false
	# Pull the two halves apart and darken them.
	# (keep_offset = true: move the edge itself, not just recalculate offsets)
	left_parts[i].set_anchor(SIDE_RIGHT, 0.43, true)
	right_parts[i].set_anchor(SIDE_LEFT, 0.57, true)
	var dark: Color = UI.wire_color(colors[i]).darkened(0.45)
	for part in [left_parts[i], right_parts[i]]:
		(part.get_meta("style") as StyleBoxFlat).bg_color = dark
	game.sfx.play("click")


## One piece of a wire: a pill shape with a soft shadow under it.
func _cable(row: Control, part_name: String, c: Color, x_min: float, x_max: float) -> Panel:
	var p := UI.panel(row, part_name, c, x_min, 0.39, x_max, 0.61, 4096)
	var sb: StyleBoxFlat = p.get_meta("style")
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 6)
	return p
