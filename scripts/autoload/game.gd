extends Node
## Persistent progress, scene flow and input map.

var SAVE_PATH := "user://profile.json"
var BACKUP_PATH := "user://profile.bak.json"
var TMP_PATH := "user://profile.tmp.json"
const SAVE_VERSION := 1
const MAX_RESULT_IDS := 32

var credits: int = 0
var car_id: String = "buggy"
var weapon_id: String = "blaster"
var upgrades: Dictionary = {}       # car_id -> {"armor": 1..3, "engine": 1..3}
var applied_results: Array = []     # IDs of race results already credited (idempotency)

## Set when the profile on disk is a newer unsupported format: never overwrite it.
var save_blocked := false
## Non-empty when the last write failed; UI shows it and offers a retry.
var save_error := ""
## Where the profile came from at startup: "new", "main", "backup", "reset".
var load_source := "new"

## Filled by the race when its result is fixed; read by the results screen.
var last_result: Dictionary = {}

## Debug-only race overrides (never active in release exports). See tests/README.
var debug_flags: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_parse_debug_args()
	load_game()


# ---------------------------------------------------------------- profile

func _default_upgrades() -> Dictionary:
	var d := {}
	for c in Cfg.CAR_IDS:
		d[c] = {"armor": 1, "engine": 1}
	return d


func _reset_profile() -> void:
	credits = 0
	car_id = "buggy"
	weapon_id = "blaster"
	upgrades = _default_upgrades()
	applied_results = []


func _profile_dict() -> Dictionary:
	return {
		"format": SAVE_VERSION,
		"credits": credits,
		"car": car_id,
		"weapon": weapon_id,
		"upgrades": upgrades.duplicate(true),
		"applied_results": applied_results.duplicate(),
	}


## Parses and validates a profile file. Returns {} when unreadable/invalid,
## {"_newer": true} for a newer unsupported format.
func read_profile(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return {}
	var data: Variant = json.data
	if not data is Dictionary:
		return {}
	var fmt := int(data.get("format", -1))
	if fmt > SAVE_VERSION:
		return {"_newer": true}
	if fmt < 1:
		return {}
	var out := {}
	var cr: Variant = data.get("credits")
	if not (cr is float or cr is int) or int(cr) < 0:
		return {}
	out["credits"] = int(cr)
	var c := str(data.get("car", ""))
	var w := str(data.get("weapon", ""))
	if not c in Cfg.CAR_IDS or not w in Cfg.WEAPON_IDS:
		return {}
	out["car"] = c
	out["weapon"] = w
	var up: Variant = data.get("upgrades")
	if not up is Dictionary:
		return {}
	var ups := {}
	for cid in Cfg.CAR_IDS:
		var e: Variant = up.get(cid)
		if not e is Dictionary:
			return {}
		var a := int(e.get("armor", 0))
		var en := int(e.get("engine", 0))
		if a < 1 or a > Cfg.MAX_LEVEL or en < 1 or en > Cfg.MAX_LEVEL:
			return {}
		ups[cid] = {"armor": a, "engine": en}
	out["upgrades"] = ups
	var ids: Variant = data.get("applied_results", [])
	out["applied_results"] = ids if ids is Array else []
	return out


func _apply_profile(d: Dictionary) -> void:
	credits = d["credits"]
	car_id = d["car"]
	weapon_id = d["weapon"]
	upgrades = d["upgrades"]
	applied_results = d["applied_results"]


func load_game() -> void:
	_reset_profile()
	save_blocked = false
	var main := read_profile(SAVE_PATH)
	if main.get("_newer", false):
		save_blocked = true
		load_source = "newer"
		push_warning("Profile has a newer format; running with defaults and not saving")
		return
	if not main.is_empty():
		_apply_profile(main)
		load_source = "main"
		return
	var bak := read_profile(BACKUP_PATH)
	if not bak.is_empty() and not bak.get("_newer", false):
		_apply_profile(bak)
		load_source = "backup"
		push_warning("Main profile unreadable, restored from backup")
		save_game()
		return
	load_source = "reset" if FileAccess.file_exists(SAVE_PATH) else "new"


## Writes temp file, verifies it, keeps the previous valid profile as backup, then replaces.
func _write_profile(d: Dictionary) -> bool:
	if save_blocked:
		save_error = "Profile was written by a newer version; saving is disabled."
		return false
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		save_error = "Cannot write profile (%s)." % error_string(FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	if read_profile(TMP_PATH).is_empty():
		save_error = "Profile verification failed."
		return false
	var abs_main := ProjectSettings.globalize_path(SAVE_PATH)
	var abs_bak := ProjectSettings.globalize_path(BACKUP_PATH)
	if not read_profile(SAVE_PATH).is_empty():
		if FileAccess.file_exists(BACKUP_PATH):
			DirAccess.remove_absolute(abs_bak)
		DirAccess.rename_absolute(abs_main, abs_bak)
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(abs_main)
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(TMP_PATH), abs_main)
	if err != OK:
		save_error = "Cannot replace profile (%s)." % error_string(err)
		return false
	save_error = ""
	return true


func save_game() -> bool:
	return _write_profile(_profile_dict())


## Applies a change to a copy of the profile; memory is updated only if the write succeeds.
func _transact(change: Callable) -> bool:
	var d := _profile_dict()
	change.call(d)
	if not _write_profile(d):
		return false
	_apply_profile(d)
	return true


func level(cid: String, kind: String) -> int:
	return int(upgrades[cid][kind])


func can_upgrade(cid: String, kind: String) -> bool:
	var lv := level(cid, kind)
	return lv < Cfg.MAX_LEVEL and credits >= Cfg.upgrade_cost(lv)


func buy_upgrade(cid: String, kind: String) -> bool:
	if not can_upgrade(cid, kind):
		return false
	var lv := level(cid, kind)
	return _transact(func(d: Dictionary) -> void:
		d["credits"] -= Cfg.upgrade_cost(lv)
		d["upgrades"][cid][kind] = lv + 1)


func select(cid: String, wid: String) -> bool:
	if not cid in Cfg.CAR_IDS or not wid in Cfg.WEAPON_IDS:
		return false
	return _transact(func(d: Dictionary) -> void:
		d["car"] = cid
		d["weapon"] = wid)


func current_stats() -> Dictionary:
	return Cfg.car_stats(car_id, level(car_id, "armor"), level(car_id, "engine"))


func is_result_applied(result_id: String) -> bool:
	return result_id in applied_results


## Credits a finished race exactly once (keyed by result id). The reward is recomputed
## from the outcome reason, never taken from the result as user input.
func commit_result(result: Dictionary) -> bool:
	last_result = result
	var rid: String = result["id"]
	if is_result_applied(rid):
		return true
	var reward := Cfg.reward_for(str(result["reason"]))
	return _transact(func(d: Dictionary) -> void:
		d["credits"] += reward
		var ids: Array = d["applied_results"]
		ids.append(rid)
		while ids.size() > MAX_RESULT_IDS:
			ids.pop_front())


func _parse_debug_args() -> void:
	# Debug overrides only in debug builds/editor, never in a release export.
	if not OS.is_debug_build():
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--debug-"):
			var kv := a.substr(8).split("=")
			debug_flags[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if debug_flags.has("profile"):
		set_profile_name(str(debug_flags["profile"]))


## Points the profile at user://profile_<name>.json (tests use an isolated profile).
func set_profile_name(n: String) -> void:
	SAVE_PATH = "user://profile_%s.json" % n
	BACKUP_PATH = "user://profile_%s.bak.json" % n
	TMP_PATH = "user://profile_%s.tmp.json" % n


# ---------------------------------------------------------------- flow

func goto_garage() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/garage.tscn")


func start_race() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/race.tscn")


func goto_results() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/results.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var mode := DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


# ---------------------------------------------------------------- input

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code   # layout-independent (works with RU layout)
	return e


func _joy_btn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func _joy_axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	return e


func _bind(action: String, events: Array, deadzone := 0.2) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
	for e in events:
		InputMap.action_add_event(action, e)


## Default layout from TASK.md. Kept in code so it can later be rebound from a settings menu.
func _setup_input() -> void:
	_bind("accelerate", [_key(KEY_W), _key(KEY_UP), _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)], 0.1)
	_bind("brake", [_key(KEY_S), _key(KEY_DOWN), _joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)], 0.1)
	_bind("steer_left", [_key(KEY_A), _key(KEY_LEFT), _joy_axis(JOY_AXIS_LEFT_X, -1.0)], 0.15)
	_bind("steer_right", [_key(KEY_D), _key(KEY_RIGHT), _joy_axis(JOY_AXIS_LEFT_X, 1.0)], 0.15)
	_bind("handbrake", [_key(KEY_SPACE), _joy_btn(JOY_BUTTON_A)])
	_bind("fire", [_key(KEY_J), _joy_btn(JOY_BUTTON_RIGHT_SHOULDER)])
	_bind("reset_car", [_key(KEY_R), _joy_btn(JOY_BUTTON_Y)])
	_bind("pause", [_key(KEY_ESCAPE), _joy_btn(JOY_BUTTON_START)])
	_bind("toggle_fullscreen", [_key(KEY_F11)])
	# Menus: Godot's ui_* already have arrows, Enter, D-pad, A/B. Add the left stick.
	_bind("ui_left", [_joy_axis(JOY_AXIS_LEFT_X, -1.0)])
	_bind("ui_right", [_joy_axis(JOY_AXIS_LEFT_X, 1.0)])
	_bind("ui_up", [_joy_axis(JOY_AXIS_LEFT_Y, -1.0)])
	_bind("ui_down", [_joy_axis(JOY_AXIS_LEFT_Y, 1.0)])
	_bind("ui_cancel", [_joy_btn(JOY_BUTTON_B)])
