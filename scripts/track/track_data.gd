class_name TrackData
extends RefCounted
## Closed track centerline: sampling, projection, checkpoints. Pure math, no nodes.
## Coordinates are (x, z) on the ground plane as Vector2. Travel direction = increasing s.

const SAMPLE_STEP := 2.0
const CHECKPOINTS := 10

## Control points: x, z, half-width. Catmull-Rom closed loop. s = 0 is the finish line.
const CONTROL := [
	Vector3(0, -55, 10), Vector3(0, 80, 10), Vector3(-10, 160, 10),          # main straight
	Vector3(-60, 215, 10.5), Vector3(-60, 280, 10.5), Vector3(10, 320, 10.5), Vector3(100, 300, 10.5),
	Vector3(165, 250, 10), Vector3(240, 240, 10), Vector3(290, 180, 9.5), Vector3(275, 110, 9),
	Vector3(225, 70, 7), Vector3(255, 20, 7), Vector3(225, -30, 7), Vector3(255, -80, 7.5),  # tight esses
	Vector3(275, -150, 9.5), Vector3(235, -220, 10), Vector3(165, -235, 10), Vector3(115, -205, 9.5),
	Vector3(60, -240, 10), Vector3(5, -210, 10), Vector3(0, -150, 10),
]

var pts := PackedVector2Array()     # centerline samples
var tans := PackedVector2Array()     # unit tangents
var half_w := PackedFloat32Array()  # half road width
var s_at := PackedFloat32Array()    # arc length at sample
var curv := PackedFloat32Array()    # signed curvature (1/m), + = turning right
var length := 0.0
var cp_s := PackedFloat32Array()    # checkpoint arc positions; cp 0 = finish line
var count := 0


func _init() -> void:
	_build()


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 \
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _build() -> void:
	# Dense spline, then resample at a fixed step.
	var dense: Array[Vector3] = []
	var n := CONTROL.size()
	for i in n:
		var p0: Vector3 = CONTROL[(i - 1 + n) % n]
		var p1: Vector3 = CONTROL[i]
		var p2: Vector3 = CONTROL[(i + 1) % n]
		var p3: Vector3 = CONTROL[(i + 2) % n]
		for k in 60:
			dense.append(_cr(p0, p1, p2, p3, k / 60.0))
	var total := 0.0
	var dl: Array[float] = [0.0]
	for i in range(1, dense.size() + 1):
		var a := dense[i - 1]
		var b := dense[i % dense.size()]
		total += Vector2(b.x - a.x, b.y - a.y).length()
		dl.append(total)
	count = int(round(total / SAMPLE_STEP))
	var step := total / count
	var j := 0
	for k in count:
		var target := k * step
		while dl[j + 1] < target:
			j += 1
		var f := (target - dl[j]) / maxf(dl[j + 1] - dl[j], 1e-6)
		var a := dense[j]
		var b := dense[(j + 1) % dense.size()]
		var p := a.lerp(b, f)
		pts.append(Vector2(p.x, p.y))
		half_w.append(p.z)
		s_at.append(target)
	length = total
	for i in count:
		var d := pts[(i + 1) % count] - pts[(i - 1 + count) % count]
		tans.append(d.normalized())
	for i in count:
		var t0 := tans[(i - 1 + count) % count]
		var t1 := tans[(i + 1) % count]
		var ang := t0.angle_to(t1)
		curv.append(ang / (2.0 * step))
	for k in CHECKPOINTS:
		cp_s.append(length * k / CHECKPOINTS)


static func right_of(t: Vector2) -> Vector2:
	return Vector2(-t.y, t.x)


func wrap_s(s: float) -> float:
	return fposmod(s, length)


## Signed shortest delta from s0 to s1 along the loop.
func delta_s(s0: float, s1: float) -> float:
	return wrapf(s1 - s0, -length * 0.5, length * 0.5)


func index_at(s: float) -> int:
	return int(wrap_s(s) / (length / count)) % count


func point_at(s: float) -> Vector2:
	s = wrap_s(s)
	var step := length / count
	var i := int(s / step) % count
	var f := (s - i * step) / step
	return pts[i].lerp(pts[(i + 1) % count], f)


func tangent_at(s: float) -> Vector2:
	s = wrap_s(s)
	var step := length / count
	var i := int(s / step) % count
	var f := (s - i * step) / step
	return tans[i].lerp(tans[(i + 1) % count], f).normalized()


func half_width_at(s: float) -> float:
	return half_w[index_at(s)]


func curvature_at(s: float) -> float:
	return curv[index_at(s)]


## Max |curvature| over [s, s + dist].
func max_curvature(s: float, dist: float) -> float:
	var step := length / count
	var i0 := index_at(s)
	var m := 0.0
	for k in int(dist / step) + 1:
		m = maxf(m, absf(curv[(i0 + k) % count]))
	return m


## World position + heading helper: heading so that forward = (sin h, cos h).
static func heading_of(t: Vector2) -> float:
	return atan2(t.x, t.y)


## Projects p on the centerline. hint < 0 = global search.
## Returns {i, s, lat} where lat > 0 means right of the centerline (in travel direction).
func project(p: Vector2, hint: int = -1) -> Dictionary:
	var best_i := 0
	var best_d := INF
	if hint < 0:
		for i in count:
			var d := pts[i].distance_squared_to(p)
			if d < best_d:
				best_d = d
				best_i = i
	else:
		for k in range(-20, 21):
			var i := (hint + k + count) % count
			var d := pts[i].distance_squared_to(p)
			if d < best_d:
				best_d = d
				best_i = i
	# refine on the segment before/after the nearest sample
	var best_s := s_at[best_i]
	var best_q := pts[best_i]
	var best_dist := sqrt(best_d)
	for seg in [best_i - 1, best_i]:
		var a := pts[(seg + count) % count]
		var b := pts[(seg + 1 + count) % count]
		var ab := b - a
		var f := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * f
		var d := q.distance_to(p)
		if d <= best_dist:
			best_dist = d
			best_q = q
			best_s = wrap_s(s_at[(seg + count) % count] + f * ab.length())
	var t := tangent_at(best_s)
	var lat := (p - best_q).dot(right_of(t))
	return {"i": best_i, "s": best_s, "lat": lat}


## True when any other part of the track centerline is closer than r to p (excluding near s).
func is_near_other_section(p: Vector2, s: float, r: float) -> bool:
	var step := length / count
	var skip := int((r * 2.5) / step)
	var i0 := index_at(s)
	for i in count:
		var di := absi(i - i0)
		di = mini(di, count - di)
		if di <= skip:
			continue
		if pts[i].distance_to(p) < r + half_w[i]:
			return true
	return false


## Minimum distance from p to the centerline minus local half-width (negative = on road).
func distance_to_road_edge(p: Vector2) -> float:
	var m := INF
	for i in range(0, count, 2):
		m = minf(m, pts[i].distance_to(p) - half_w[i])
	return m
