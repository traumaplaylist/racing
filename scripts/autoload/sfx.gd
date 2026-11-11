extends Node
## Procedurally synthesized sound effects (no third-party audio assets).

const RATE := 22050

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams["blaster"] = _make(0.09, func(t: float, k: float) -> float:
		return _sq(t * lerpf(1100.0, 520.0, k)) * 0.35 * (1.0 - k))
	_streams["pulse"] = _make(0.38, func(t: float, k: float) -> float:
		var f := lerpf(260.0, 55.0, sqrt(k))
		return (sin(TAU * f * t) * 0.7 + _noise() * 0.25 * (1.0 - k)) * pow(1.0 - k, 1.5) * 0.8)
	_streams["hit"] = _make(0.08, func(t: float, k: float) -> float:
		return (_noise() * 0.6 + sin(TAU * 320.0 * t) * 0.4) * (1.0 - k) * 0.6)
	_streams["hit_heavy"] = _make(0.18, func(t: float, k: float) -> float:
		return (_noise() * 0.7 + sin(TAU * 140.0 * t) * 0.5) * pow(1.0 - k, 2.0) * 0.8)
	_streams["bump"] = _make(0.12, func(t: float, k: float) -> float:
		return (_noise() * 0.5 + sin(TAU * 90.0 * t)) * pow(1.0 - k, 2.0) * 0.5)
	_streams["pickup_repair"] = _make(0.3, func(t: float, k: float) -> float:
		var f := 523.0 if k < 0.33 else (659.0 if k < 0.66 else 784.0)
		return sin(TAU * f * t) * 0.35 * (1.0 - k * 0.5))
	_streams["pickup_boost"] = _make(0.35, func(t: float, k: float) -> float:
		return _sq(t * lerpf(300.0, 900.0, k)) * 0.22 * (1.0 - k * 0.6))
	_streams["explode"] = _make(0.9, func(t: float, k: float) -> float:
		return (_noise() * 0.8 + sin(TAU * 50.0 * t) * 0.5) * pow(1.0 - k, 2.2))
	_streams["beep"] = _make(0.18, func(t: float, k: float) -> float:
		return sin(TAU * 660.0 * t) * 0.4 * (1.0 - k))
	_streams["go"] = _make(0.45, func(t: float, k: float) -> float:
		return sin(TAU * 990.0 * t) * 0.45 * (1.0 - k))
	_streams["ui_move"] = _make(0.04, func(t: float, k: float) -> float:
		return sin(TAU * 880.0 * t) * 0.15 * (1.0 - k))
	_streams["ui_ok"] = _make(0.12, func(t: float, k: float) -> float:
		return sin(TAU * lerpf(660.0, 990.0, k) * t) * 0.25 * (1.0 - k))
	_streams["ui_deny"] = _make(0.15, func(t: float, k: float) -> float:
		return _sq(t * 140.0) * 0.15 * (1.0 - k))


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


static func _sq(phase: float) -> float:
	return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0


func _make(duration: float, fn: Callable) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v: float = clampf(fn.call(t, float(i) / n), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## volume 0..1, pitch multiplier.
func play(sound: String, volume := 1.0, pitch := 1.0) -> void:
	if not _streams.has(sound) or volume <= 0.02:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.volume_db = linear_to_db(volume)
	p.pitch_scale = pitch
	p.play()
