# vault_module.gd
# -----------------------------------------------------------------------------
# Base class for every security module (Wires, Button, Keypad).
# A module:
#   1) builds its own UI inside itself (build),
#   2) checks the player's action against PuzzleRules,
#   3) calls solve(...) or strike(...). The GameManager handles the rest
#      (strike counter, sounds, status message, win/lose).
# To add a new module: create a script that extends this one.
# -----------------------------------------------------------------------------
extends Control

const UI = preload("res://scripts/ui_factory.gd")
const PuzzleRules = preload("res://scripts/puzzle_rules.gd")
const VaultId = preload("res://scripts/vault_id.gd")

var game: Node # the GameManager (main.gd)
var vault_id: VaultId
var rng: RandomNumberGenerator
var is_solved := false


## Called once by the GameManager right after the module is created.
func init_module(p_game: Node, mission: Dictionary, p_vault_id: VaultId, p_rng: RandomNumberGenerator) -> void:
	game = p_game
	vault_id = p_vault_id
	rng = p_rng
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build(mission)


## Name shown on the module tab, e.g. "WIRES". Override in each module.
func display_name() -> String:
	return "MODULE"


## The correct answer as text - printed to the Output panel for testing.
func solution_for_debug() -> String:
	return ""


## Create the random puzzle and its UI. Override in each module.
func build(_mission: Dictionary) -> void:
	pass


## True while the player is allowed to interact with this module.
func can_act() -> bool:
	return not is_solved and game != null and game.is_playing()


func solve(message: String) -> void:
	if is_solved:
		return
	is_solved = true
	_show_disarmed_banner()
	game.on_module_solved(self, message)


func strike(message: String) -> void:
	game.on_strike(self, message)


## Common header: title on top, hint at the bottom. Returns the hint label.
func create_header(title: String, hint: String) -> Label:
	var band := UI.panel(self, "TitleBand", Color(0, 0, 0, 0.35), 0.08, 0.905, 0.92, 0.985, 16)
	UI.caps(band, "Title", title, 38, UI.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 0.02, 0, 0.98, 1, 5)
	return UI.text(self, "Hint", hint, 34, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.04, 0.01, 0.96, 0.08)


## Dims the module and slams a green "DISARMED" stamp on it.
func _show_disarmed_banner() -> void:
	UI.rect(self, "Dim", Color(0.02, 0.05, 0.04, 0.55), 0, 0, 1, 1)
	var stamp := UI.panel(self, "DisarmedStamp", Color(0.04, 0.20, 0.11, 0.94), 0.10, 0.40, 0.90, 0.60, 22, UI.GOOD, 9)
	UI.caps(stamp, "Text", "DISARMED", 92, UI.GOOD, HORIZONTAL_ALIGNMENT_CENTER, 0, 0, 1, 1, 8)
	stamp.pivot_offset = stamp.size * 0.5
	stamp.rotation = deg_to_rad(-7.0)
	stamp.scale = Vector2.ONE * 1.5
	stamp.modulate.a = 0.0
	var tw := stamp.create_tween().set_parallel(true)
	tw.tween_property(stamp, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_IN)
	tw.tween_property(stamp, "modulate:a", 1.0, 0.12)
