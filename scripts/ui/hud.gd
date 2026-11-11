class_name Hud
extends CanvasLayer
## In-race HUD + pause menu. Reads race state; never changes rules.

var race: RaceManager
var lap_l: Label
var pos_l: Label
var rivals_l: Label
var time_l: Label
var hp_l: Label
var hp_bar: Control
var weapon_l: Label
var ready_l: Label
var ready_bar: Control
var boost_box: Control
var boost_bar: Control
var speed_l: Label
var count_l: Label
var msg_l: Label
var hint_l: Label
var hit_l: Label
var dmg_flash: ColorRect
var pause_root: Control
var _msg_t := 0.0
var _hit_t := 0.0
var _dmg_t := 0.0
var _slow_t := 0.0


func bind(p_race: RaceManager) -> void:
	race = p_race
	layer = 5
	_build()
	race.message.connect(_on_message)
	race.player_hit_target.connect(func(_t: RaceCar) -> void: _hit_t = 0.35)
	race.player_damaged.connect(func() -> void: _dmg_t = 0.35)


func _anchor(c: Control, preset: Control.LayoutPreset, margin := 20) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, margin)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	dmg_flash = ColorRect.new()
	dmg_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	dmg_flash.color = Color(1, 0.15, 0.05, 0.0)
	dmg_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dmg_flash)

	# top-left: lap, position, rivals left
	var tl := UiKit.panel()
	var tlv := VBoxContainer.new()
	tlv.add_theme_constant_override("separation", 0)
	tl.add_child(tlv)
	lap_l = UiKit.label("", 34)
	pos_l = UiKit.label("", 30, UiKit.ACCENT)
	rivals_l = UiKit.label("", 22, UiKit.WARM)
	time_l = UiKit.label("", 20, UiKit.DIM)
	for l in [lap_l, pos_l, rivals_l, time_l]:
		tlv.add_child(l)
	root.add_child(tl)
	_anchor(tl, Control.PRESET_TOP_LEFT)

	# bottom-left: HP
	var bl := UiKit.panel()
	var blv := VBoxContainer.new()
	bl.add_child(blv)
	var hrow := HBoxContainer.new()
	hrow.add_child(UiKit.label(Loc.t("hud_hp"), 22, UiKit.DIM))
	hp_l = UiKit.label("", 34)
	hp_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hrow.add_child(hp_l)
	blv.add_child(hrow)
	hp_bar = UiKit.bar(300, 24, UiKit.GOOD)
	blv.add_child(hp_bar)
	root.add_child(bl)
	_anchor(bl, Control.PRESET_BOTTOM_LEFT)

	# bottom-right: weapon readiness, boost timer, speed
	var br := UiKit.panel()
	var brv := VBoxContainer.new()
	br.add_child(brv)
	var wrow := HBoxContainer.new()
	weapon_l = UiKit.label("", 26)
	weapon_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrow.add_child(weapon_l)
	hit_l = UiKit.label("HIT", 26, UiKit.WARM)
	hit_l.modulate.a = 0.0
	wrow.add_child(hit_l)
	brv.add_child(wrow)
	var rrow := HBoxContainer.new()
	ready_bar = UiKit.bar(220, 20, UiKit.ACCENT)
	ready_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rrow.add_child(ready_bar)
	ready_l = UiKit.label("", 20)
	ready_l.custom_minimum_size.x = 100
	ready_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rrow.add_child(ready_l)
	brv.add_child(rrow)
	boost_box = HBoxContainer.new()
	boost_bar = UiKit.bar(220, 20, UiKit.WARM)
	boost_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	boost_box.add_child(boost_bar)
	var bl2 := UiKit.label(Loc.t("hud_boost") + " »", 20, UiKit.WARM)
	bl2.custom_minimum_size.x = 100
	bl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	boost_box.add_child(bl2)
	brv.add_child(boost_box)
	speed_l = UiKit.label("", 18, UiKit.DIM)
	speed_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	brv.add_child(speed_l)
	root.add_child(br)
	_anchor(br, Control.PRESET_BOTTOM_RIGHT)

	# center: countdown and messages
	count_l = UiKit.label("", 120, UiKit.TEXT, 12)
	count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(count_l)
	_anchor(count_l, Control.PRESET_CENTER_TOP, 150)
	count_l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	msg_l = UiKit.label("", 44, UiKit.TEXT, 10)
	msg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(msg_l)
	_anchor(msg_l, Control.PRESET_CENTER_TOP, 40)
	msg_l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_l = UiKit.label("", 22, UiKit.WARM, 6)
	hint_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint_l)
	_anchor(hint_l, Control.PRESET_CENTER_BOTTOM, 30)
	hint_l.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_build_pause(root)


func _build_pause(root: Control) -> void:
	pause_root = Control.new()
	pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	pause_root.visible = false
	root.add_child(pause_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.add_child(center)
	var p := UiKit.panel(UiKit.BG_SOLID)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size.x = 380
	p.add_child(v)
	var t := UiKit.label(Loc.t("pause_title"), 44)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var resume := UiKit.button(Loc.t("pause_resume"), 28, true)
	var restart := UiKit.button(Loc.t("pause_restart"), 26)
	var garage := UiKit.button(Loc.t("pause_garage"), 26)
	for b in [resume, restart, garage]:
		b.custom_minimum_size.y = 60
		v.add_child(b)
	resume.pressed.connect(set_paused.bind(false))
	restart.pressed.connect(func() -> void: Game.start_race())     # 0 CR
	garage.pressed.connect(func() -> void: Game.goto_garage())    # 0 CR
	pause_root.set_meta("first", resume)


func set_paused(on: bool) -> void:
	if on and race.phase == RaceManager.Phase.ENDED:
		return
	get_tree().paused = on
	pause_root.visible = on
	if on:
		(pause_root.get_meta("first") as Button).grab_focus()
		Sfx.play("ui_ok")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif get_tree().paused and event.is_action_pressed("ui_cancel"):
		set_paused(false)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# losing window focus pauses the race (stops the timer too)
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and race and race.phase == RaceManager.Phase.RACING:
		set_paused(true)


func _on_message(text: String, color: Color) -> void:
	if text == "":
		return
	msg_l.text = text
	UiKit.set_label_color(msg_l, color)
	_msg_t = 2.0


func _process(delta: float) -> void:
	if race == null:
		return
	var p := race.player
	lap_l.text = Loc.t("hud_lap", [race.current_lap(p), Cfg.LAPS])
	pos_l.text = Loc.t("hud_pos", [race.position_of(p), Cfg.RACER_COUNT])
	rivals_l.text = Loc.t("hud_rivals", [race.rivals_left()])
	time_l.text = _fmt_time(race.race_time)
	var hp := ceili(p.hp)
	hp_l.text = "%d / %d" % [hp, int(p.max_hp)]
	var frac := p.hp / p.max_hp
	var hc := UiKit.GOOD if frac > 0.5 else (UiKit.WARM if frac > 0.25 else UiKit.BAD)
	UiKit.set_bar(hp_bar, frac, hc)
	weapon_l.text = Loc.t("weapon_" + p.weapon_id)
	var rf := p.weapon_ready_frac()
	UiKit.set_bar(ready_bar, rf, UiKit.ACCENT if rf >= 1.0 else UiKit.DIM)
	ready_l.text = Loc.t("hud_ready") if rf >= 1.0 else Loc.t("hud_reload")
	UiKit.set_label_color(ready_l, UiKit.ACCENT if rf >= 1.0 else UiKit.DIM)
	boost_box.modulate.a = 1.0 if p.boost_t > 0.0 else 0.0
	UiKit.set_bar(boost_bar, p.boost_t / Cfg.BOOST_TIME)
	speed_l.text = "%d %s" % [roundi(absf(p.vf) * 3.6), Loc.t("hud_kmh")]

	if race.phase == RaceManager.Phase.COUNTDOWN:
		count_l.text = str(ceili(race.countdown))
	else:
		count_l.text = ""
	_msg_t -= delta
	msg_l.modulate.a = clampf(_msg_t, 0.0, 1.0)
	_hit_t -= delta
	hit_l.modulate.a = clampf(_hit_t / 0.35, 0.0, 1.0)
	_dmg_t -= delta
	dmg_flash.color.a = clampf(_dmg_t, 0.0, 0.35) * 0.6

	# hints: wrong way / stuck → reset
	if race.phase == RaceManager.Phase.RACING and p.alive:
		_slow_t = _slow_t + delta if p.speed() < 2.0 else 0.0
		if p.wrong_way_t > 1.0:
			hint_l.text = Loc.t("hud_wrong_way") + "   ·   " + Loc.t("hud_reset_hint")
		elif _slow_t > 2.0:
			hint_l.text = Loc.t("hud_reset_hint")
		else:
			hint_l.text = ""
	else:
		hint_l.text = ""


static func _fmt_time(t: float) -> String:
	var m := int(t) / 60
	var s := fmod(t, 60.0)
	return "%d:%05.2f" % [m, s]
