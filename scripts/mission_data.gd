# mission_data.gd
# -----------------------------------------------------------------------------
# Settings for each mission. To tweak difficulty, change the numbers here.
#
# side_times: every module side has its own timer (seconds). The timer starts
# when the Operator taps the side open, and the vault stays locked on that side
# until it is disarmed. If a side timer reaches 0:00 the alarm goes off.
# Keys are the module names: WIRES, BUTTON, KEYPAD, WORDS.
# -----------------------------------------------------------------------------
extends RefCounted

const MISSIONS := [
	{
		"title": "MISSION 1",
		"subtitle": "TRAINING SAFE",
		"side_times": {"WIRES": 120, "BUTTON": 120}, # 2:00 each
		"min_wires": 3,
		"max_wires": 4,
		"has_keypad": false, # Wires + Button
		"has_word_lock": false,
	},
	{
		"title": "MISSION 2",
		"subtitle": "BANK VAULT",
		"side_times": {"WIRES": 90, "BUTTON": 90, "KEYPAD": 120},
		"min_wires": 4,
		"max_wires": 5,
		"has_keypad": true, # Wires + Button + Keypad
		"has_word_lock": false,
	},
	{
		"title": "MISSION 3",
		"subtitle": "CENTRAL RESERVE",
		"side_times": {"WIRES": 75, "BUTTON": 75, "KEYPAD": 105, "WORDS": 180},
		"min_wires": 4,
		"max_wires": 5,
		"has_keypad": true,
		"has_word_lock": true, # Wires + Button + Keypad + Word Lock (bottom side)
	},
]


static func count() -> int:
	return MISSIONS.size()


static func get_mission(index: int) -> Dictionary:
	return MISSIONS[index]


## How many module sides the mission has (shown on the menu card).
static func side_count(index: int) -> int:
	return (MISSIONS[index]["side_times"] as Dictionary).size()


## Seconds the given module side gets in this mission.
static func side_time(mission: Dictionary, module_name: String) -> float:
	return float((mission["side_times"] as Dictionary).get(module_name, 90))
