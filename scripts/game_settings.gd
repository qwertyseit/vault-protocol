# game_settings.gd
# -----------------------------------------------------------------------------
# Player settings, saved in user://settings.cfg so they stay after a restart.
#   sound        - sound effects on/off
#   vibration    - phone vibration on a strike on/off
#   spin_speed   - how fast the vault turns under the finger (0 slow, 1 normal, 2 fast)
#   tutorial_seen - the How to play screen opens by itself only on the first start
# -----------------------------------------------------------------------------
extends RefCounted

const PATH := "user://settings.cfg"
const SPIN_SPEEDS := [0.0035, 0.005, 0.0068] # radians per pixel of dragging
const SPIN_NAMES := ["SLOW", "NORMAL", "FAST"]

var sound := true
var vibration := true
var spin_speed := 1
var tutorial_seen := false


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return # first start: keep the defaults
	sound = cfg.get_value("audio", "sound", true)
	vibration = cfg.get_value("device", "vibration", true)
	spin_speed = clampi(cfg.get_value("controls", "spin_speed", 1), 0, SPIN_SPEEDS.size() - 1)
	tutorial_seen = cfg.get_value("general", "tutorial_seen", false)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sound", sound)
	cfg.set_value("device", "vibration", vibration)
	cfg.set_value("controls", "spin_speed", spin_speed)
	cfg.set_value("general", "tutorial_seen", tutorial_seen)
	cfg.save(PATH)


func rotate_speed() -> float:
	return SPIN_SPEEDS[spin_speed]
