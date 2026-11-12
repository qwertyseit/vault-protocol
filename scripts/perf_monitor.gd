# perf_monitor.gd
# -----------------------------------------------------------------------------
# Performance overlay for testing on the phone (Settings -> PERF MONITOR).
#   Line 1 (live):  frames per second, frame time, draw calls per frame,
#                   video memory, how many vault sides are redrawn per frame.
#   Line 2 (test):  measured only while a mission is being played (not paused):
#                   test duration, average FPS, 1% low FPS, worst frame time,
#                   average draw calls per frame.
# The test restarts with every mission. Tapping the overlay switches the
# vault between "redraw only the visible sides" (v0.4) and "redraw all sides"
# (the old v0.3 behaviour), so both can be measured with the same test.
# Numbers come from Godot: the frame delta, Engine.get_frames_per_second()
# and RenderingServer.get_rendering_info().
# -----------------------------------------------------------------------------
extends Control

const UI = preload("res://scripts/ui_factory.gd")
const REFRESH := 0.25 # seconds between text updates

var game: Node # the GameManager (main.gd), set by main.gd
var vault: Node # vault_3d.gd, set by main.gd

var _live: Label
var _test: Label
var _refresh := 0.0

# test statistics
var _frames := 0
var _time := 0.0
var _draw_calls_sum := 0.0
var _deltas := PackedFloat32Array()
var _worst := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tap := UI.touch_area(self, "Tap", 0, 0, 1, 1, _toggle_redraw_mode)
	UI.panel(tap, "Back", Color(0, 0, 0, 0.72), 0, 0, 1, 1, 14, Color(UI.GOOD, 0.5), 2)
	_live = UI.caps(tap, "Live", "", 24, UI.GOOD, HORIZONTAL_ALIGNMENT_LEFT, 0.03, 0.52, 0.97, 0.96, 2)
	_test = UI.caps(tap, "Test", "", 24, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 0.03, 0.04, 0.97, 0.48, 2)
	for l in [_live, _test]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## Starts a new measurement (called when a mission starts).
func reset_test() -> void:
	_frames = 0
	_time = 0.0
	_draw_calls_sum = 0.0
	_deltas.clear()
	_worst = 0.0
	_refresh = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	if game != null and game.is_playing():
		_frames += 1
		_time += delta
		_draw_calls_sum += draw_calls
		_deltas.append(delta)
		_worst = maxf(_worst, delta)

	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = REFRESH

	var vram_mb := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
	var sides := 0
	if vault != null:
		sides = vault.redrawn_faces()
	_live.text = "NOW  %d FPS  •  %.1f MS  •  %d DRAW CALLS\nVRAM %.0f MB  •  SIDES REDRAWN %d / 6" % [
		Engine.get_frames_per_second(), delta * 1000.0, draw_calls, vram_mb, sides]

	var mode := "ALL SIDES" if (vault != null and vault.redraw_all_faces) else "VISIBLE SIDES"
	if _frames < 2:
		_test.text = "TEST  %s  •  TAP TO SWITCH\nstarts when a mission is played" % mode
		return
	_test.text = "TEST  %s  •  %s\nAVG %.1f FPS  •  1%% LOW %.0f FPS  •  WORST %.0f MS  •  %.0f DC" % [
		mode, UI.format_time(_time), _frames / _time, _one_percent_low(), _worst * 1000.0, _draw_calls_sum / _frames]


## FPS of the slowest 1% of frames.
func _one_percent_low() -> float:
	var sorted := _deltas.duplicate()
	sorted.sort()
	var index := int(sorted.size() * 0.99)
	index = clampi(index, 0, sorted.size() - 1)
	var slow := sorted[index]
	return 1.0 / slow if slow > 0.0 else 0.0


func _toggle_redraw_mode() -> void:
	if vault == null:
		return
	vault.redraw_all_faces = not vault.redraw_all_faces
	reset_test()
