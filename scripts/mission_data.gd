# mission_data.gd
# -----------------------------------------------------------------------------
# Settings for each mission. To tweak difficulty, change the numbers here.
# -----------------------------------------------------------------------------
extends RefCounted

const MISSIONS := [
	{
		"title": "MISSION 1",
		"subtitle": "TRAINING SAFE",
		"time_limit": 300, # 5:00
		"min_wires": 3,
		"max_wires": 4,
		"has_keypad": false, # Wires + Button
	},
	{
		"title": "MISSION 2",
		"subtitle": "BANK VAULT",
		"time_limit": 240, # 4:00
		"min_wires": 4,
		"max_wires": 5,
		"has_keypad": true, # Wires + Button + Keypad
	},
]


static func count() -> int:
	return MISSIONS.size()


static func get_mission(index: int) -> Dictionary:
	return MISSIONS[index]
