class_name EngineAudio
extends AudioStreamPlayer
## Continuous player engine + tyre-slide sound synthesized into an AudioStreamGenerator.

const RATE := 22050.0

var rpm := 0.0          # 0..1
var engine_load := 0.0         # throttle 0..1
var slide := 0.0        # 0..1 drift amount
var _phase := 0.0
var _phase2 := 0.0
var _noise_lp := 0.0
var _pb: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	stream = gen
	volume_db = -6.0
	play()
	_pb = get_stream_playback()


func _process(_d: float) -> void:
	if _pb == null:
		return
	var frames := _pb.get_frames_available()
	var f0 := 38.0 + rpm * 120.0
	var amp := 0.16 + engine_load * 0.1
	for i in frames:
		_phase = fmod(_phase + f0 / RATE, 1.0)
		_phase2 = fmod(_phase2 + f0 * 0.5 / RATE, 1.0)
		var saw := _phase * 2.0 - 1.0
		var sub := sin(TAU * _phase2)
		var e := (saw * 0.55 + sub * 0.45) * amp
		_noise_lp = lerpf(_noise_lp, _rng.randf_range(-1.0, 1.0), 0.25)
		var n := _noise_lp * slide * 0.35
		var v := clampf(e + n, -1.0, 1.0)
		_pb.push_frame(Vector2(v, v))
