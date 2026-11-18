# tension_music.gd
# -----------------------------------------------------------------------------
# Background music made in code (v0.5, from the Assignment 4 feedback), so like
# sound_fx.gd it needs no audio files. Three layers:
#   DRONE - a low, slowly beating chord that always plays during a mission,
#   BEAT  - a heartbeat ("lub-dub") that gets faster as time runs out,
#   TENSE - a high, trembling clash that fades in near the end.
# The GameManager calls set_intensity(0..1) every frame:
#   0   = no side is open (only the calm drone),
#   0.25 .. 1 = the open side with the least time left is running out.
# The music stays quiet on purpose: the players still have to hear each other.
# It can be switched off in Settings (MUSIC).
# -----------------------------------------------------------------------------
extends Node

const RATE := 11025 # low notes only, so a low sample rate is enough (and fast to build)

var enabled := true

var _drone: AudioStreamPlayer
var _tense: AudioStreamPlayer
var _beat: AudioStreamPlayer
var _running := false
var _paused := false
var _target := 0.0
var _intensity := 0.0 # follows _target smoothly
var _beat_wait := 0.0


func _ready() -> void:
	_drone = _make_player("Drone", _build_drone())
	_tense = _make_player("Tense", _build_tense())
	_beat = _make_player("Beat", _build_beat())


## A mission starts: calm drone from the beginning.
func start() -> void:
	_running = true
	_paused = false
	_target = 0.0
	_intensity = 0.0
	_beat_wait = 0.5
	_set_paused_players(false)
	_apply_volumes()
	if enabled:
		_drone.play()
		_tense.play()


## The mission is over (win, alarm, menu).
func stop() -> void:
	_running = false
	for p in [_drone, _tense, _beat]:
		p.stop()


func set_paused(on: bool) -> void:
	_paused = on
	_set_paused_players(on)


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		for p in [_drone, _tense, _beat]:
			p.stop()
	elif _running and not _drone.playing:
		_drone.play()
		_tense.play()
		_set_paused_players(_paused)


func set_intensity(value: float) -> void:
	_target = clampf(value, 0.0, 1.0)


func _process(delta: float) -> void:
	if not _running or _paused or not enabled:
		return
	_intensity = move_toward(_intensity, _target, delta * 0.6)
	_apply_volumes()

	# heartbeat: 60 beats per minute when calm, 150 at the very end
	_beat_wait -= delta
	if _beat_wait <= 0.0:
		_beat_wait = 60.0 / lerpf(60.0, 150.0, _intensity)
		if _target > 0.0:
			_beat.volume_db = lerpf(-19.0, -8.0, _intensity)
			_beat.play()


func _apply_volumes() -> void:
	_drone.volume_db = lerpf(-19.0, -13.0, _intensity)
	_drone.pitch_scale = lerpf(1.0, 1.06, _intensity) # the chord slowly rises
	var tense_amount := clampf((_intensity - 0.5) / 0.5, 0.0, 1.0)
	_tense.volume_db = linear_to_db(maxf(tense_amount, 0.0001)) - 15.0


func _set_paused_players(on: bool) -> void:
	for p in [_drone, _tense, _beat]:
		p.stream_paused = on


# =============================================================================
# Sounds (built once at start)
# =============================================================================

## Soft saturation: adds overtones, so low notes are heard on phone speakers too.
static func _warm(x: float) -> float:
	return tanh(2.2 * x) / tanh(2.2)


## 2-second loop. Every frequency makes a whole number of waves in 2 seconds,
## so the loop has no click.
func _build_drone() -> AudioStreamWAV:
	var n := RATE * 2
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / RATE
		var swell := 0.80 + 0.20 * sin(TAU * 0.5 * t)
		var v := 0.34 * sin(TAU * 110.0 * t) \
			+ 0.22 * sin(TAU * 110.5 * t) \
			+ 0.20 * sin(TAU * 164.5 * t) \
			+ 0.12 * sin(TAU * 220.0 * t)
		samples[i] = _warm(v * swell) * 0.55
	return _to_wav(samples, true)


## 2-second loop: two close notes (they clash) with a fast tremble.
func _build_tense() -> AudioStreamWAV:
	var n := RATE * 2
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / RATE
		var tremble := 0.55 + 0.45 * sin(TAU * 6.0 * t)
		var v := 0.5 * sin(TAU * 440.0 * t) + 0.5 * sin(TAU * 466.0 * t)
		samples[i] = v * tremble * 0.45
	return _to_wav(samples, true)


## One heartbeat: a strong thump and a softer one right after it.
func _build_beat() -> AudioStreamWAV:
	var n := int(RATE * 0.42)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for hit in [[0.0, 1.0], [0.17, 0.65]]:
		var start := int(hit[0] * RATE)
		var phase := 0.0
		for i in range(start, n):
			var t := float(i - start) / RATE
			var f := 60.0 + 110.0 * exp(-t * 25.0) # the pitch falls fast: a thump
			phase += TAU * f / RATE
			var env := exp(-t * 22.0)
			if i - start < 40:
				env *= float(i - start) / 40.0 # tiny fade-in, no click
			samples[i] += hit[1] * env * (sin(phase) + 0.35 * sin(2.0 * phase))
	for i in n:
		samples[i] = _warm(samples[i] * 0.8)
	return _to_wav(samples, false)


func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


func _make_player(player_name: String, stream: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	add_child(player)
	return player
