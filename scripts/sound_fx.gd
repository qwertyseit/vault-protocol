# sound_fx.gd
# -----------------------------------------------------------------------------
# Simple beeps generated in code (sine / square waves), so the prototype needs
# no audio files and has no licence questions. Replace with real sounds later.
# -----------------------------------------------------------------------------
extends Node

const RATE := 22050

var _players := {}


func _ready() -> void:
	_make("click", [900.0], 0.04, 0.35, false)
	_make("good", [1200.0], 0.07, 0.35, false)
	_make("solved", [660.0, 990.0], 0.11, 0.45, false)
	_make("strike", [140.0, 110.0], 0.20, 0.40, true)
	_make("tick", [1500.0], 0.025, 0.25, false)
	_make("win", [523.0, 659.0, 784.0, 1047.0], 0.12, 0.45, false)
	_make("alarm", [880.0, 587.0, 880.0, 587.0, 880.0, 587.0], 0.16, 0.35, true)
	_make("start", [440.0, 880.0], 0.08, 0.35, false)


func play(sound: String) -> void:
	if _players.has(sound):
		_players[sound].play()


## Builds a sound that plays the given frequencies one after another.
func _make(sound: String, freqs: Array, note_seconds: float, volume: float, square: bool) -> void:
	var per_note := int(note_seconds * RATE)
	var fade := mini(per_note / 4, int(0.008 * RATE)) # short fade avoids clicks
	var data := PackedByteArray()
	data.resize(per_note * freqs.size() * 2) # 16-bit samples = 2 bytes each
	var index := 0
	for f in freqs:
		for i in per_note:
			var t := float(i) / RATE
			var wave := sin(TAU * f * t)
			if square:
				wave = 0.6 if wave >= 0.0 else -0.6
			var env := 1.0
			if i < fade:
				env = float(i) / fade
			elif i > per_note - fade:
				env = float(per_note - i) / fade
			data.encode_s16(index * 2, int(clampf(wave * env * volume, -1.0, 1.0) * 32767.0))
			index += 1

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data

	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.max_polyphony = 4
	add_child(player)
	_players[sound] = player
