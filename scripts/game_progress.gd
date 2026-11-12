# game_progress.gd
# -----------------------------------------------------------------------------
# Mission records, saved in user://progress.cfg so they stay after a restart.
# For every mission we keep the best (fastest) clear:
#   time    - seconds from the start of the mission to the last disarmed side
#   strikes - strikes made in that run
#   clears  - how many times the mission was cleared
# All missions are always open: this is a party game, players pick the
# difficulty they want. Records can be reset in Settings.
# -----------------------------------------------------------------------------
extends RefCounted

const PATH := "user://progress.cfg"

var records := {} # mission index -> {"time": float, "strikes": int, "clears": int}


func load_progress() -> void:
	records.clear()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return # first start: no records yet
	for section in cfg.get_sections():
		if not section.begins_with("mission_"):
			continue
		var index := int(section.substr(8))
		records[index] = {
			"time": float(cfg.get_value(section, "best_time", 0.0)),
			"strikes": int(cfg.get_value(section, "best_strikes", 0)),
			"clears": int(cfg.get_value(section, "clears", 0)),
		}


func save_progress() -> void:
	var cfg := ConfigFile.new()
	for index in records:
		var r: Dictionary = records[index]
		var section := "mission_%d" % index
		cfg.set_value(section, "best_time", r["time"])
		cfg.set_value(section, "best_strikes", r["strikes"])
		cfg.set_value(section, "clears", r["clears"])
	cfg.save(PATH)


func has_record(index: int) -> bool:
	return records.has(index)


func get_record(index: int) -> Dictionary:
	return records.get(index, {})


## Called after a win. Returns true when this run is a new best time.
func submit_clear(index: int, time: float, strikes: int) -> bool:
	var r: Dictionary = records.get(index, {})
	var is_best: bool = r.is_empty() or time < float(r["time"])
	if is_best:
		records[index] = {"time": time, "strikes": strikes, "clears": int(r.get("clears", 0)) + 1}
	else:
		r["clears"] = int(r["clears"]) + 1
	save_progress()
	return is_best


func reset() -> void:
	records.clear()
	save_progress()
