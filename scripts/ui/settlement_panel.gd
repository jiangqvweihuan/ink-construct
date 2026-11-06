extends CanvasLayer

## 结算长卷：左侧「终局对演 / 收剑落款」，右侧战绩与本局收获。
## 阵亡按真实攻击者、招式、命中时刻和实际扣血重演；通关以胜利动作与讨伐印落款。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Skulls = preload("res://scripts/player/skulls.gd")
const EnemyTypes = preload("res://scripts/enemies/enemy_types.gd")
const BossTypes = preload("res://scripts/enemies/boss_types.gd")
const SpineFX := preload("res://scripts/systems/spine_fx.gd")
const SFX_SETTLE := preload("res://audio/sfx/settle.wav")
const SFX_WIN := preload("res://audio/sfx/win.wav")
const SFX_LOSE := preload("res://audio/sfx/lose.wav")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.66, 0.2, 0.16)
const GOLD := Color(0.9, 0.75, 0.3)

var _title := "结  算"
var _cleared := false
var _avatar: Node2D
var _enemy: Node2D
var _avatar_state
var _enemy_state
var _avatar_data
var _duel_done := false
var _hit_shown := false
var _result_fx: Node2D
var _result_anim := ""
var _last_hit_fx: Node2D


func setup(title_text: String, cleared := false) -> void:
	_title = title_text
	_cleared = cleared


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_play_sound(SFX_SETTLE)
	_play_sound(SFX_WIN if _cleared else SFX_LOSE)

	var diff: Dictionary = {"mastery": {}, "unlocks": []}
	if not Run.meta_snapshot.is_empty():
		diff = Meta.diff_since(Run.meta_snapshot)
	var ink_gain := Meta.deposit_ink(Score.kills, Run.cleared_room_count(), _cleared, Run.c023_ink_bonus)
	_build(diff, ink_gain)


func _build(diff: Dictionary, ink_gain: int) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.size = Vector2(1160, 600)
	win.position = Vector2(60, 60)
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)
	_make_result_fx()

	if _title not in ["通  关", "阵  亡"]:
		_text(_title, Vector2(60, 78), Vector2(1160, 54), 42, PAPER)
	_text(_journey_text(), Vector2(60, 138), Vector2(1160, 28), 16, DIM)
	_rule(Vector2(180, 178), Vector2(920, 1))
	_rule(Vector2(638, 204), Vector2(1, 408))

	_text("收 剑 落 款" if _cleared else "终 局 对 演", Vector2(100, 198), Vector2(500, 32), 21, RED)
	_rule(Vector2(130, 540), Vector2(440, 2))
	_make_avatar()
	if _cleared:
		_make_seals()
	else:
		_make_enemy()
		_make_skip_area()
		_text("殁于 · %s" % _enemy_label(), Vector2(100, 566), Vector2(500, 30), 19, RED)
		_text("点击左侧可跳过对演 · 右侧抉择始终可用", Vector2(100, 604), Vector2(500, 22), 12, DIM)
		_play_duel()

	_text("行 旅 记", Vector2(680, 198), Vector2(500, 32), 20, PAPER)
	_make_line("%s · %s ｜ 历程 %s" % [Run.mode_label(), Run.difficulty_label(), _progress_text()], DIM, 17, 232)
	_make_line("最高连击 %d ｜ 击杀 %d ｜ 已清房间 %d" % [Score.max_combo, Score.kills, Run.cleared_room_count()], PAPER, 18, 266)
	var cy := 306.0
	if _cleared and not _defeated_ids().is_empty():
		_make_line("讨伐落款 · %s" % _defeated_names(), RED, 19, cy)
		cy += 36.0

	var rows := 0
	for id in diff["mastery"]:
		if rows >= 3 or cy > 430.0:
			break
		var old_exp := int(Run.meta_snapshot.get("mastery", {}).get(id, 0))
		_make_mastery_row(str(id), int(diff["mastery"][id]), old_exp, cy, rows)
		cy += 44.0
		rows += 1
	for id in diff["unlocks"]:
		if cy > 450.0:
			break
		_make_line("新化身 · %s %s" % [str(Skulls.get_profile(id)["label"]), str(Skulls.get_profile(id).get("name", ""))], RED, 18, cy)
		cy += 30.0
	if ink_gain > 0 and cy <= 460.0:
		var ink_text := "墨锭 +%d（总 %d）" % [ink_gain, Meta.ink]
		if Run.c023_ink_bonus > 0:
			ink_text = "墨锭 +%d（墨梅 +%d｜总 %d）" % [ink_gain, Run.c023_ink_bonus, Meta.ink]
		_make_line(ink_text, PAPER, 19, cy)
		cy += 30.0
	if rows == 0 and diff["unlocks"].is_empty() and ink_gain <= 0:
		_make_line("本局无额外收获", DIM, 17, cy)

	_make_button("再来一局", 508, _restart)
	_make_button("回主菜单", 574, _to_menu)


func _make_result_fx() -> void:
	_result_anim = "win" if _cleared else "lose"
	_result_fx = SpineFX.spawn(self, "E21013", Vector2(640, 92), {
		"anim": _result_anim, "scale": 0.36, "center": true, "loop": false, "auto_free": false,
		"always": true, "z": 0, "mod": Color(1, 1, 1, 0.62),
	})
	if _result_fx != null:
		_result_fx.name = "SettlementResultSpineFX"


func _journey_text() -> String:
	return "%s · %s ｜ %s" % [Run.mode_label(), Run.difficulty_label(), "收剑有印，行旅有痕" if _cleared else "最后一击，如实重演"]


func _progress_text() -> String:
	if Run.mode == Run.MODE_ENDLESS:
		return "第 %d 层" % Run.depth
	return "墨堂深处" if Run.room_index >= Run.ROOMS.size() else "第 %d / %d 关" % [Run.room_index + 1, Run.ROOMS.size()]


func _make_avatar() -> void:
	var profile: Dictionary = Skulls.get_profile(Run.skull_id)
	_avatar_data = load(str(profile["data"]))
	if _avatar_data == null or not _avatar_data.call("is_skeleton_data_loaded"):
		return
	_avatar = ClassDB.instantiate("SpineSprite")
	_avatar.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_avatar)
	_avatar.set("skeleton_data_res", _avatar_data)
	_avatar_data.call("set_default_mix", 0.16)
	var sc := float(profile["scale"]) * (1.75 if _cleared else 1.65)
	_avatar.scale = Vector2(sc if _cleared else -sc, sc)
	_avatar.position = Vector2(350 if _cleared else 458, 536)
	_avatar_state = _avatar.call("get_animation_state")
	var anim_map: Dictionary = profile["anim"]
	if _cleared:
		var pool: Array = profile.get("victory", [])
		if pool.is_empty():
			_avatar_state.call("set_animation", str(anim_map["idle"]), true, 0)
		else:
			_avatar_state.call("set_animation", str(pool[randi() % pool.size()]), false, 0)
			_avatar_state.call("add_animation", str(anim_map["idle"]), 0.0, true, 0)
	elif Run.last_hit.is_empty():
		_avatar_dead()
	else:
		_avatar_state.call("set_animation", str(anim_map["idle"]), true, 0)


func _enemy_config() -> Dictionary:
	var id := str(Run.last_hit.get("type_id", ""))
	if BossTypes.BOSSES.has(id):
		return BossTypes.get_boss(id)
	if EnemyTypes.TYPES.has(id):
		return EnemyTypes.get_type(id)
	return {}


func _enemy_label() -> String:
	if Run.last_hit.is_empty():
		return "命火自熄"
	var cfg := _enemy_config()
	return str(cfg.get("label", "无名墨影"))


func _make_enemy() -> void:
	var cfg := _enemy_config()
	if cfg.is_empty() or _avatar_state == null:
		_avatar_dead()
		_duel_done = true
		return
	var data = load(str(cfg["data"]))
	if data == null or not data.call("is_skeleton_data_loaded"):
		_avatar_dead()
		_duel_done = true
		return
	_enemy = ClassDB.instantiate("SpineSprite")
	_enemy.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_enemy)
	_enemy.set("skeleton_data_res", data)
	data.call("set_default_mix", 0.12)
	var is_boss := BossTypes.BOSSES.has(str(Run.last_hit.get("type_id", "")))
	var sc := float(cfg["scale"]) * (0.86 if is_boss else 1.5)
	_enemy.scale = Vector2(sc, sc)
	_enemy.position = Vector2(244, 536)
	_enemy_state = _enemy.call("get_animation_state")
	_enemy_state.call("set_animation", str(cfg["anim"]["idle"]), true, 0)


func _play_duel() -> void:
	if _duel_done or _enemy_state == null or _avatar_state == null:
		return
	await get_tree().create_timer(0.3, true).timeout
	if _duel_done or not is_inside_tree():
		return
	var cfg := _enemy_config()
	var anim := str(Run.last_hit.get("anim", cfg["anim"]["idle"]))
	if data_has_animation(_enemy.get("skeleton_data_res"), anim) == false:
		anim = str(cfg["anim"]["idle"])
	_enemy_state.call("set_animation", anim, false, 0)
	_enemy_state.call("add_animation", str(cfg["anim"]["idle"]), 0.0, true, 0)
	await get_tree().create_timer(float(Run.last_hit.get("hit_at", 0.65)), true).timeout
	if _duel_done or not is_inside_tree():
		return
	_show_last_hit()
	var profile: Dictionary = Skulls.get_profile(Run.skull_id)
	var hurt_anim := str(profile["anim"]["hurt"])
	_avatar_state.call("set_animation", hurt_anim, false, 0)
	await get_tree().create_timer(minf(0.42, _animation_duration(_avatar_data, hurt_anim, 0.3)), true).timeout
	if not _duel_done and is_inside_tree():
		_finish_duel()


func data_has_animation(data, anim: String) -> bool:
	return data != null and data.call("find_animation", anim) != null


func _animation_duration(data, anim: String, fallback: float) -> float:
	if data == null:
		return fallback
	var a = data.call("find_animation", anim)
	return float(a.call("get_duration")) if a != null else fallback


func _finish_duel() -> void:
	if _duel_done:
		return
	_duel_done = true
	if _enemy_state != null:
		var cfg := _enemy_config()
		if not cfg.is_empty():
			_enemy_state.call("set_animation", str(cfg["anim"]["idle"]), true, 0)
	_avatar_dead()
	_show_last_hit()


func _avatar_dead() -> void:
	if _avatar_state == null:
		return
	var anim_map: Dictionary = Skulls.get_profile(Run.skull_id)["anim"]
	_avatar_state.call("set_animation", str(anim_map["dead"]), false, 0)
	var hold := str(anim_map.get("dead_hold", ""))
	if hold != "":
		_avatar_state.call("add_animation", hold, 0.0, true, 0)


func _make_skip_area() -> void:
	var b := Button.new()
	b.flat = true
	b.position = Vector2(100, 232)
	b.size = Vector2(510, 326)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(_finish_duel)
	add_child(b)


func _show_last_hit() -> void:
	if _hit_shown:
		return
	_hit_shown = true
	_last_hit_fx = SpineFX.spawn(self, "E50041", Vector2(458, 424), {
		"anim": "action", "width": 260.0, "always": true, "auto_free": false, "z": 0,
	})
	if _last_hit_fx != null:
		_last_hit_fx.name = "LastHitSpineFX"
	var damage := int(Run.last_hit.get("damage", 0))
	if damage > 0:
		var l := Label.new()
		l.name = "LastHitDamage"
		l.text = "-%d" % damage
		l.position = Vector2(456, 388)
		l.size = Vector2(80, 40)
		l.add_theme_color_override("font_color", RED)
		l.add_theme_font_size_override("font_size", 26)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		var dt := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		dt.set_parallel(true)
		dt.tween_property(l, "position:y", 350.0, 0.65)
		dt.tween_property(l, "modulate:a", 0.0, 0.65)


func _defeated_ids() -> Array:
	if not Run.boss_defeated.is_empty():
		return Run.boss_defeated
	return [Run.boss_id] if BossTypes.BOSSES.has(Run.boss_id) else []


func _defeated_names() -> String:
	var names: Array = []
	for id in _defeated_ids():
		if BossTypes.BOSSES.has(str(id)):
			names.append(str(BossTypes.get_boss(str(id))["label"]))
	return " / ".join(names)


func _make_seals() -> void:
	var ids := _defeated_ids()
	for i in ids.size():
		var id := str(ids[i])
		if not BossTypes.BOSSES.has(id):
			continue
		var seal := Control.new()
		seal.position = Vector2(140 + i * 108, 284 + i * 82)
		seal.size = Vector2(96, 104)
		seal.rotation = -0.06 if i == 0 else 0.07
		add_child(seal)
		var bg := ColorRect.new()
		bg.color = Color(0.66, 0.2, 0.16, 0.9)
		bg.size = seal.size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seal.add_child(bg)
		var l := Label.new()
		l.text = "讨伐\n%s" % str(BossTypes.get_boss(id)["label"])
		l.size = seal.size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", PAPER)
		l.add_theme_font_size_override("font_size", 17)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seal.add_child(l)


func _make_line(text: String, color: Color, font_size: int, y: float) -> void:
	_text(text, Vector2(680, y), Vector2(500, 30), font_size, color)


func _make_mastery_row(id: String, gain: int, old_exp: int, y: float, row: int) -> void:
	var new_exp := Meta.mastery_exp(id)
	var lv_old := _level_of(old_exp)
	var lv_new := Meta.mastery_level(id)
	var leveled := lv_new > lv_old
	var profile: Dictionary = Skulls.get_profile(id)
	var text := "%s · %s  契合 +%d（%s）" % [str(profile["label"]), str(profile.get("name", "")), gain, Meta.mastery_text(id)]
	if leveled:
		text = "%s · %s  契合 +%d  Lv%d → Lv%d！" % [str(profile["label"]), str(profile.get("name", "")), gain, lv_old, lv_new]
	_make_line(text, RED if leveled else PAPER, 17, y)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.55)
	bar_bg.size = Vector2(320, 9)
	bar_bg.position = Vector2(770, y + 29)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_bg)
	var fill := ColorRect.new()
	fill.color = RED
	fill.size = Vector2(_frac_of(old_exp) * 320.0, 9)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(fill)
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(fill, "size:x", _frac_of(new_exp) * 320.0, 0.7) \
		.set_delay(0.35 + row * 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _level_of(exp: int) -> int:
	var lv := 0
	for need in Meta.LV_EXP:
		if exp >= int(need):
			lv += 1
	return lv


func _frac_of(exp: int) -> float:
	var prev := 0
	for need in Meta.LV_EXP:
		var n := int(need)
		if exp < n:
			return float(exp - prev) / float(n - prev)
		prev = n
	return 1.0


func _restart() -> void:
	get_tree().paused = false
	Run.start(Run.mode, Run.skull_id, Run.difficulty)
	await LoadVeil.transition_reload("正在重入此卷")


func _to_menu() -> void:
	get_tree().paused = false
	await LoadVeil.transition_to("res://scenes/ui/main_menu.tscn", "正在合卷")


func _text(text: String, pos: Vector2, size: Vector2, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


func _rule(pos: Vector2, size: Vector2) -> void:
	var r := ColorRect.new()
	r.color = Color(0.66, 0.2, 0.16, 0.62)
	r.position = pos
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)


func _make_button(text: String, y: float, cb: Callable) -> void:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load("res://art/ui/menu/btn_normal.png")
	b.texture_pressed = InkTex.load("res://art/ui/menu/btn_clicked.png")
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(220, 52)
	b.position = Vector2(820, y)
	var l := Label.new()
	l.text = text
	l.size = b.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", INK)
	l.add_theme_font_size_override("font_size", 21)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	b.pressed.connect(func():
		_play_transition_sound(SFX_CLICK)
		cb.call())
	add_child(b)


func _play_sound(stream: AudioStream) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(s)
	s.stream = stream
	s.play()


func _play_transition_sound(stream: AudioStream) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(s)
	s.stream = stream
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)
