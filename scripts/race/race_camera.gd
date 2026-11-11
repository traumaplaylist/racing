class_name RaceCamera
extends Camera3D
## Tilted top-down chase camera. Only the camera is smoothed; it follows the body axis
## (also while reversing) and composes the player low in the frame with room ahead.

@export var pitch_deg := 61.0
@export var car_screen_y := 0.68         # player position from the top of the frame
@export var dist_slow := 29.0            # camera→car distance when stopped
@export var dist_fast := 39.0            # at top speed (pulls back to show turns earlier)
@export var yaw_smooth := 4.5
@export var dist_smooth := 1.5

var target: RaceCar
var _yaw := 0.0
var _dist := 29.0
var _shake := 0.0
var _init_done := false


func _ready() -> void:
	fov = 50.0
	near = 1.0
	far = 1500.0


func snap() -> void:
	if target:
		_yaw = target.heading
		_dist = dist_slow
		_init_done = true
		_update_transform()


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	if target == null:
		return
	if not _init_done:
		snap()
	_yaw = lerp_angle(_yaw, target.heading, 1.0 - exp(-yaw_smooth * delta))
	var top: float = target.stats["vmax"]
	var k := clampf(absf(target.vf) / top, 0.0, 1.0)
	_dist = lerpf(_dist, lerpf(dist_slow, dist_fast, k), 1.0 - exp(-dist_smooth * delta))
	_shake = maxf(0.0, _shake - delta * 3.0)
	_update_transform()


func _update_transform() -> void:
	var theta := deg_to_rad(pitch_deg)
	# angle between the optical axis and the ray to the car that puts the car at car_screen_y
	var delta_ang := atan((car_screen_y - 0.5) * 2.0 * tan(deg_to_rad(fov) * 0.5))
	var alpha := theta + delta_ang
	var fwd := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var car_p := Vector3(target.pos.x, 0.8, target.pos.y)
	var p := car_p - fwd * _dist * cos(alpha) + Vector3.UP * _dist * sin(alpha)
	if _shake > 0.0:
		p += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.6
	global_transform = Transform3D(Basis.from_euler(Vector3(-theta, _yaw + PI, 0.0)), p)
