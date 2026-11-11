extends Node
## Results: outcome + concrete reason, place or DNF status, time, kills, reward. Retry / Garage.

var show: Showroom
var _busy := false
var err_l: Label
var retry_save: Button


func _ready() -> void:
	var r: Dictionary = Game.last_result
	if r.is_empty():
		Game.goto_garage()
		return
	show = Showroom.new()
	add_child(show)
	show.build(str(r["car"]), RaceManager.PLAYER_COLOR, -3.0)
	show.spin = 0.2
	_build_ui(r)


func _row(v: VBoxContainer, k: String, val: String, color := UiKit.TEXT) -> void:
	var h := HBoxContainer.new()
	var kl := UiKit.label(k, 22, UiKit.DIM)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(kl)
	h.add_child(UiKit.label(val, 26, color))
	v.add_child(h)


func _build_ui(r: Dictionary) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var panel := UiKit.panel()
	root.add_child(panel)
	panel.anchor_left = 0.0
	panel.anchor_right = 0.48
	panel.anchor_bottom = 1.0
	panel.offset_left = 28
	panel.offset_top = 28
	panel.offset_bottom = -28
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var win: bool = r["outcome"] == "win"
	v.add_child(UiKit.label(Loc.t("results_win") if win else Loc.t("results_loss"), 64,
		UiKit.GOOD if win else UiKit.BAD, 8))
	var reason := Loc.t("reason_" + str(r["reason"]), [r.get("rival", "")])
	var rl := UiKit.label(reason, 24)
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(rl)
	v.add_child(HSeparator.new())
	if r["player_finished"]:
		_row(v, Loc.t("results_place"), "%s / %d" % [Loc.place(int(r["place"])), Cfg.RACER_COUNT], UiKit.ACCENT)
	elif not r["player_alive"]:
		_row(v, Loc.t("results_status"), Loc.t("status_destroyed"), UiKit.BAD)
	elif win:
		_row(v, Loc.t("results_place"), "%s / %d" % [Loc.place(1), Cfg.RACER_COUNT], UiKit.ACCENT)
	else:
		_row(v, Loc.t("results_status"), Loc.t("status_dnf", [Loc.place(int(r["place"]))]), UiKit.WARM)
	_row(v, Loc.t("results_time"), Hud._fmt_time(float(r["time"])))
	_row(v, Loc.t("results_kills"), str(r["kills"]))
	_row(v, Loc.t("results_reward"), "+%d CR" % int(r["reward"]), UiKit.WARM)
	_row(v, Loc.t("results_balance"), Loc.t("balance", [Game.credits]))

	err_l = UiKit.label("", 18, UiKit.BAD)
	err_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(err_l)
	retry_save = UiKit.button("Retry save", 20)
	retry_save.visible = false
	retry_save.pressed.connect(_retry_save)
	v.add_child(retry_save)
	_update_save_state()

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var retry := UiKit.button(Loc.t("results_retry"), 30, true)
	var garage := UiKit.button(Loc.t("results_garage"), 30)
	for b in [retry, garage]:
		b.custom_minimum_size.y = 70
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
	v.add_child(h)
	retry.pressed.connect(func() -> void: _go(Game.start_race))
	garage.pressed.connect(func() -> void: _go(Game.goto_garage))
	retry.grab_focus()


func _update_save_state() -> void:
	var ok := Game.is_result_applied(str(Game.last_result["id"]))
	err_l.text = "" if ok else "Could not save the reward: %s" % Game.save_error
	retry_save.visible = not ok


func _retry_save() -> void:
	Game.commit_result(Game.last_result)   # idempotent by result id
	_update_save_state()


func _go(f: Callable) -> void:
	if _busy:
		return
	_busy = true
	Sfx.play("ui_ok")
	f.call()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go(Game.goto_garage)
