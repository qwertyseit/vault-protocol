# puzzle_rules.gd
# -----------------------------------------------------------------------------
# ALL puzzle rules of Vault Protocol live in this one file.
# The Technical Manual (PDF) describes exactly these rules, in the same order.
# If you change a rule here, change the manual too (and the other way round).
# -----------------------------------------------------------------------------
extends RefCounted

const VaultId = preload("res://scripts/vault_id.gd")

enum WireColor { RED, BLUE, YELLOW, WHITE, GREEN }
enum ButtonColor { RED, BLUE, YELLOW, WHITE }
enum ButtonLabel { OPEN, LOCK, HOLD, RESET }
enum LightColor { WHITE, BLUE, YELLOW, RED }

const WIRE_NAMES := ["RED", "BLUE", "YELLOW", "WHITE", "GREEN"]
const BUTTON_COLOR_NAMES := ["RED", "BLUE", "YELLOW", "WHITE"]
const BUTTON_LABEL_NAMES := ["OPEN", "LOCK", "HOLD", "RESET"]
const LIGHT_NAMES := ["WHITE", "BLUE", "YELLOW", "RED"]


# =============================================================================
# MODULE 1 - WIRES (3, 4 or 5 wires, numbered 1..N from the top)
# Check the rules for your wire count from top to bottom.
# Follow the FIRST rule that is true.
# Returns a 0-based index (0 = wire 1).
# =============================================================================
static func wire_to_cut(w: Array, id: VaultId) -> int:
	var n := w.size()

	if n == 3:
		# 1. Wire 1 and wire 3 are the same color -> cut wire 2.
		if w[0] == w[2]:
			return 1
		# 2. There is a YELLOW wire -> cut the first (top-most) yellow wire.
		var first_yellow := w.find(WireColor.YELLOW)
		if first_yellow >= 0:
			return first_yellow
		# 3. Otherwise -> cut wire 1.
		return 0

	if n == 4:
		# 1. Two or more RED wires -> cut the last (bottom-most) red wire.
		if w.count(WireColor.RED) >= 2:
			return w.rfind(WireColor.RED)
		# 2. Vault ID ends in an ODD digit and there is a BLUE wire -> cut the first blue wire.
		if id.last_digit_is_odd() and w.has(WireColor.BLUE):
			return w.find(WireColor.BLUE)
		# 3. There is no GREEN wire -> cut wire 3.
		if not w.has(WireColor.GREEN):
			return 2
		# 4. Otherwise -> cut wire 4.
		return 3

	if n == 5:
		# 1. Wire 5 (the bottom wire) is GREEN -> cut wire 4.
		if w[4] == WireColor.GREEN:
			return 3
		# 2. There is exactly one WHITE wire -> cut the white wire.
		if w.count(WireColor.WHITE) == 1:
			return w.find(WireColor.WHITE)
		# 3. Vault ID ends in an EVEN digit -> cut wire 1.
		if not id.last_digit_is_odd():
			return 0
		# 4. Otherwise -> cut wire 3.
		return 2

	push_error("Wires module supports only 3, 4 or 5 wires.")
	return 0


# =============================================================================
# MODULE 2 - OVERRIDE BUTTON
# Step A: decide TAP or HOLD (first true rule wins).
# Step B (only for HOLD): while holding, a light turns on and the PIN COUNTER
#         counts 1..9 (and starts again). Release when the counter shows the
#         number for the light color.
# =============================================================================
static func button_should_hold(color: int, label: int, id: VaultId) -> bool:
	# 1. The label says HOLD -> TAP. (Never trust the label!)
	if label == ButtonLabel.HOLD:
		return false
	# 2. The button is YELLOW -> HOLD.
	if color == ButtonColor.YELLOW:
		return true
	# 3. The label says LOCK and the Vault ID ends in an EVEN digit -> TAP.
	if label == ButtonLabel.LOCK and not id.last_digit_is_odd():
		return false
	# 4. The button is WHITE -> TAP.
	if color == ButtonColor.WHITE:
		return false
	# 5. Otherwise -> HOLD.
	return true


## Which PIN COUNTER number to release on, by light color.
static func release_number(light: int) -> int:
	match light:
		LightColor.WHITE:
			return 3
		LightColor.BLUE:
			return 6
		LightColor.YELLOW:
			return 2
		_:
			return 8 # RED


# =============================================================================
# MODULE 3 - SYMBOL KEYPAD (4 keys)
# Every symbol has a code number in the manual table.
# Vault ID has NO vowel -> press from the LOWEST code to the HIGHEST.
# Vault ID has a vowel  -> press from the HIGHEST code to the LOWEST.
# =============================================================================

# Symbol glyphs and their code numbers (same order in both arrays).
const SYMBOL_GLYPHS := [
	"Ω", # Omega
	"Δ", # Delta
	"Ψ", # Psi
	"Σ", # Sigma
	"λ", # lambda
	"π", # pi
	"Φ", # Phi
	"Ξ", # Xi
	"¥", # Yen
	"£", # Pound
	"€", # Euro
	"§", # Section sign
	"¶", # Pilcrow
	"Ж", # Cyrillic Zhe
	"Ю", # Cyrillic Yu
	"¿", # Inverted question mark
]

const SYMBOL_CODES := [41, 17, 88, 23, 65, 9, 72, 34, 56, 12, 97, 48, 81, 30, 63, 5]


## key_symbols[i] = symbol index shown on key position i.
## Returns key positions in the order they must be pressed.
static func keypad_order(key_symbols: Array, id: VaultId) -> Array:
	var positions := []
	for i in key_symbols.size():
		positions.append(i)
	var descending := id.has_vowel()
	positions.sort_custom(func(a, b):
		var code_a: int = SYMBOL_CODES[key_symbols[a]]
		var code_b: int = SYMBOL_CODES[key_symbols[b]]
		return code_a > code_b if descending else code_a < code_b
	)
	return positions


# =============================================================================
# MODULE 4 - WORD LOCK (Mission 3, bottom side of the vault)
# A screen shows a word (or nothing). Six buttons below show six words.
# Step 1: the SCREEN word tells which button to READ (table 1).
# Step 2: the word on that button gives a list (table 2). Press the button
#         with the FIRST word of that list that is on the panel.
# Three stages; every stage shows new words.
# =============================================================================
const WORD_LOCK_SCREEN := ["KEY", "KEYS", "QUAY", "SAFE", "SAVE", "CODE", "COLD", "LOCKED", "LOCK IT", "ZERO", "OH", ""]

## Button to read for each screen word.
# 0 = top left, 1 = top right, 2 = middle left, 3 = middle right, 4 = bottom left, 5 = bottom right
const WORD_LOCK_READ := [3, 4, 1, 5, 0, 2, 5, 1, 2, 4, 3, 0]
const WORD_LOCK_POSITIONS := ["TOP LEFT", "TOP RIGHT", "MIDDLE LEFT", "MIDDLE RIGHT", "BOTTOM LEFT", "BOTTOM RIGHT"]

const WORD_LOCK_WORDS := ["STEEL", "STEAL", "CASH", "CACHE", "BREAK", "BRAKE", "HOLE", "WHOLE", "TWO", "TOO", "KNOW", "NOW"]

## Step 2 lists: button word -> words in the order to look for them.
const WORD_LOCK_LISTS := {
	"STEEL": ["BREAK", "NOW", "WHOLE", "STEAL", "BRAKE", "CASH", "TOO", "TWO", "HOLE", "KNOW", "CACHE", "STEEL"],
	"STEAL": ["NOW", "STEAL", "TWO", "STEEL", "BRAKE", "HOLE", "KNOW", "WHOLE", "TOO", "BREAK", "CACHE", "CASH"],
	"CASH": ["STEAL", "BREAK", "BRAKE", "STEEL", "KNOW", "CASH", "CACHE", "TOO", "WHOLE", "TWO", "HOLE", "NOW"],
	"CACHE": ["STEEL", "KNOW", "STEAL", "WHOLE", "NOW", "TOO", "TWO", "CACHE", "HOLE", "BRAKE", "CASH", "BREAK"],
	"BREAK": ["BREAK", "CASH", "WHOLE", "TOO", "NOW", "STEEL", "STEAL", "BRAKE", "TWO", "HOLE", "KNOW", "CACHE"],
	"BRAKE": ["KNOW", "TWO", "NOW", "CACHE", "HOLE", "BRAKE", "BREAK", "CASH", "TOO", "WHOLE", "STEAL", "STEEL"],
	"HOLE": ["BREAK", "NOW", "STEAL", "KNOW", "STEEL", "CASH", "HOLE", "TOO", "WHOLE", "TWO", "BRAKE", "CACHE"],
	"WHOLE": ["HOLE", "BREAK", "STEAL", "CACHE", "WHOLE", "STEEL", "BRAKE", "KNOW", "TOO", "TWO", "CASH", "NOW"],
	"TWO": ["STEEL", "TOO", "HOLE", "TWO", "NOW", "KNOW", "CACHE", "WHOLE", "STEAL", "BREAK", "CASH", "BRAKE"],
	"TOO": ["HOLE", "STEAL", "KNOW", "STEEL", "NOW", "BRAKE", "CASH", "TWO", "WHOLE", "BREAK", "TOO", "CACHE"],
	"KNOW": ["CACHE", "TWO", "BRAKE", "CASH", "TOO", "WHOLE", "STEEL", "NOW", "KNOW", "HOLE", "BREAK", "STEAL"],
	"NOW": ["TOO", "BREAK", "KNOW", "CACHE", "STEAL", "STEEL", "CASH", "NOW", "WHOLE", "TWO", "BRAKE", "HOLE"],
}


## screen: index in WORD_LOCK_SCREEN. buttons: the 6 words on the panel
## (index 0 = top left ... 5 = bottom right). Returns the button to press.
static func word_lock_answer(screen: int, buttons: Array) -> int:
	var read_word: String = buttons[WORD_LOCK_READ[screen]]
	for word in WORD_LOCK_LISTS[read_word]:
		var position := buttons.find(word)
		if position >= 0:
			return position
	return WORD_LOCK_READ[screen] # never reached: the read word is always on the panel
