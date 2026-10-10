# vault_id.gd
# -----------------------------------------------------------------------------
# The Vault ID printed on the vault, e.g. "QAE-582".
# Format: 3 letters, a dash, 3 digits. Several rules depend on it.
# -----------------------------------------------------------------------------
extends RefCounted

const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const VOWELS := "AEIOU" # Y is NOT a vowel

var code: String


func _init(p_code: String = "") -> void:
	code = p_code


## The last character of the code is always a digit.
func last_digit() -> int:
	return code.substr(code.length() - 1, 1).to_int()


func last_digit_is_odd() -> bool:
	return last_digit() % 2 == 1


## True if the code contains A, E, I, O or U.
func has_vowel() -> bool:
	for ch in code:
		if VOWELS.contains(ch):
			return true
	return false


## A random code like "QAE-582". Use: VaultId.new(VaultId.random_code(rng))
static func random_code(rng: RandomNumberGenerator) -> String:
	var s := ""
	for i in 3:
		s += LETTERS[rng.randi_range(0, LETTERS.length() - 1)]
	s += "-"
	for i in 3:
		s += str(rng.randi_range(0, 9))
	return s
