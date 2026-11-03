extends CanvasLayer

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const Settings = preload("res://scripts/ui/settings.gd")
const VitalBar = preload("res://scripts/ui/vital_bar.gd")
const BattleStatus = preload("res://scripts/ui/battle_status.gd")

## 水墨 HUD：多层生命条、右上战斗状态、底部带招式名与数值冷却的技能栏。

const BAR_W := 380.0
const BAR_H := 30.0
const SLOT := 56.0
const SLOT_GAP := 70.0
const VERMILION := Color(0.659, 0.196, 0.165)
const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.76, 0.73, 0.66)
const GOLD := Color(0.91, 0.75, 0.34)
const BOSS_FONT = preload("res://art/ui/fonts/slidefu_regular.ttf")

var _root: Control
var _action_root: Control
var _hp_bar: Control
var _hp_label: Label
var _combo_label: Label
var _mode_label: Label
var _hud_skills: Array = []
var _cd_masks: Array = []
var _cd_labels: Array = []
var _lock_labels: Array = []
var _player: Node2D
var _player_extra := 0
var _boss_bar: Control
var _boss_vital: Control
var _boss_name: Label
var _boss_extra := 0
var _status_panel: Panel
var _status_signature := ""
var _status_clock := 0.0


func _rect(tex_path: String, dimensions: Vector2, pos: Vector2, parent: Control) -> TextureRect:
	var t := TextureRect.new()
	t.texture = InkTex.load(tex_path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = dimensions
	t.position = pos
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_hp_bar(_root)
	_build_combo(_root)
	_build_mode_label(_root)
	_build_status(_root)
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		_player.hp_changed.connect(_on_hp_changed)
		_player.skull_changed.connect(_on_skull_changed)
		_player_extra = int(_player.call("hud_extra_hp"))
		_on_hp_changed(_player.hp, _player.max_hp)
		_hud_skills = _player.hud_skills
	_build_action_bar(_root)
	_sync_status(true)
	Score.combo_changed.connect(_on_combo_changed)
	_on_combo_changed(Score.combo)


func _build_hp_bar(root: Control) -> void:
	var bar := Control.new()
	bar.position = Vector2(18, 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	_hp_bar = VitalBar.new()
	_hp_bar.bar_width = BAR_W
	_hp_bar.bar_height = BAR_H
	bar.add_child(_hp_bar)
	_hp_label = Label.new()
	_hp_label.position = Vector2(12, 4)
	_hp_label.size = Vector2(BAR_W - 24, BAR_H)
	_hp_label.add_theme_color_override("font_color", PAPER)
	_hp_label.add_theme_color_override("font_outline_color", INK)
	_hp_label.add_theme_constant_override("outline_size", 3)
	_hp_label.add_theme_font_size_override("font_size", 15)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_hp_label)


# ---------- 底部动作栏 ----------

func _build_action_bar(root: Control) -> void:
	if _action_root != null and is_instance_valid(_action_root):
		_action_root.queue_free()
	_action_root = Control.new()
	_action_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_action_root)
	_cd_masks.clear()
	_cd_labels.clear()
	_lock_labels.clear()
	var slot_count: int = 1 + _hud_skills.size()
	var gap := SLOT_GAP if slot_count <= 6 else 60.0
	var total_w := gap * float(slot_count - 1) + SLOT
	var splat_w := maxf(340.0, total_w + 100.0)
	var splat := _rect("res://art/ui/hud/action_splat.png", Vector2(splat_w, 104), Vector2(640.0 - splat_w * 0.5, 624), _action_root)
	splat.modulate = Color(1, 1, 1, 0.94)
	var start_x := 640.0 - total_w * 0.5
	for i in slot_count:
		var x := start_x + i * gap
		var y := 650.0
		var skill_id := "" if i == 0 else str(_hud_skills[i - 1])
		var title := "普攻" if i == 0 else BattleStatus.skill_name(_player, i - 1)
		var name_label := _label(title, Vector2(x - 16, y - 25), Vector2(SLOT + 32, 22), 13, PAPER, _action_root)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.add_theme_color_override("font_outline_color", INK)
		name_label.add_theme_constant_override("outline_size", 4)
		_rect("res://art/ui/hud/skill_slot.png", Vector2(SLOT, SLOT), Vector2(x, y), _action_root)
		var mask := ColorRect.new()
		mask.color = Color(0.025, 0.025, 0.025, 0.76)
		mask.position = Vector2(x + 3, y + 3)
		mask.size = Vector2(SLOT - 6, 0)
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mask.visible = false
		_action_root.add_child(mask)
		_cd_masks.append(mask)
		var key := Settings.action_label("attack") if i == 0 else str(_player.get_skill_key(skill_id))
		var key_label := _label(key, Vector2(x, y + 3), Vector2(SLOT, SLOT - 6), 23, PAPER, _action_root)
		key_label.add_theme_color_override("font_outline_color", INK)
		key_label.add_theme_constant_override("outline_size", 3)
		var cd_label := _label("", Vector2(x, y + 3), Vector2(SLOT, SLOT - 6), 20, PAPER, _action_root)
		cd_label.add_theme_color_override("font_outline_color", INK)
		cd_label.add_theme_constant_override("outline_size", 5)
		cd_label.visible = false
		_cd_labels.append(cd_label)
		var lock := _label("", Vector2(x - 4, y + SLOT - 17), Vector2(SLOT + 8, 18), 11, Color(1.0, 0.55, 0.42), _action_root)
		lock.add_theme_color_override("font_outline_color", INK)
		lock.add_theme_constant_override("outline_size", 3)
		lock.visible = false
		_lock_labels.append(lock)


func _label(text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color, parent: Control) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = dimensions
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _update_action_bar() -> void:
	for i in _hud_skills.size():
		if i + 1 >= _cd_masks.size():
			break
		var skill_id := str(_hud_skills[i])
		var ratio: float = _player.get_skill_cd_ratio(skill_id)
		var left := BattleStatus.skill_cooldown(_player, skill_id)
		var mask: ColorRect = _cd_masks[i + 1]
		var cd_label: Label = _cd_labels[i + 1]
		mask.visible = ratio > 0.001
		cd_label.visible = left > 0.05
		if mask.visible:
			var h := (SLOT - 6) * ratio
			mask.size.y = h
			mask.position.y = 653.0 + (SLOT - 6 - h)
		if cd_label.visible:
			cd_label.text = "%.1f" % left if left < 3.0 else str(int(ceil(left)))
		var lock_text := BattleStatus.skill_lock(_player, skill_id) if ratio <= 0.001 else ""
		var lock_label: Label = _lock_labels[i + 1]
		lock_label.visible = lock_text != ""
		lock_label.text = lock_text


# ---------- 右上状态区 ----------

func _build_status(root: Control) -> void:
	_status_panel = Panel.new()
	_status_panel.position = Vector2(948, 12)
	_status_panel.size = Vector2(320, 70)
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.035, 0.035, 0.76)
	sb.set_border_width_all(1)
	sb.border_color = Color(PAPER, 0.24)
	sb.set_corner_radius_all(7)
	_status_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_status_panel)


func _sync_status(force := false) -> void:
	if _status_panel == null or _player == null or not is_instance_valid(_player):
		return
	var list: Array = BattleStatus.entries(_player)
	var signature := JSON.stringify(list)
	if not force and signature == _status_signature:
		return
	_status_signature = signature
	for c in _status_panel.get_children():
		_status_panel.remove_child(c)
		c.queue_free()
	_label("战斗状态", Vector2(12, 5), Vector2(130, 24), 16, PAPER, _status_panel).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label("Esc 详览", Vector2(205, 7), Vector2(102, 20), 12, DIM, _status_panel).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var shown := mini(10, list.size())
	for i in shown:
		var entry: Dictionary = list[i]
		var col := i % 2
		var row := floori(i / 2.0)
		_status_chip(entry, Vector2(10 + col * 152, 34 + row * 31), Vector2(148, 27))
	var rows := int(ceil(shown / 2.0))
	var more := list.size() - shown
	if more > 0:
		_label("另有 %d 项 · 暂停查看全部" % more, Vector2(12, 38 + rows * 31), Vector2(296, 20), 12, DIM, _status_panel)
		rows += 1
	_status_panel.size.y = maxf(66, 40 + rows * 31)


func _status_chip(entry: Dictionary, pos: Vector2, dimensions: Vector2) -> void:
	var chip := Panel.new()
	chip.position = pos
	chip.size = dimensions
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kind := str(entry.get("kind", "passive"))
	var tint := Color(PAPER, 0.10)
	if kind == "buff":
		tint = Color(GOLD, 0.18)
	elif kind == "debuff":
		tint = Color(VERMILION, 0.30)
	elif kind == "stolen":
		tint = Color(0.56, 0.42, 0.72, 0.25)
	elif kind == "upgrade":
		tint = Color(0.40, 0.62, 0.65, 0.18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.set_corner_radius_all(4)
	chip.add_theme_stylebox_override("panel", sb)
	_status_panel.add_child(chip)
	var color := PAPER if bool(entry.get("active", true)) else Color(0.72, 0.56, 0.52)
	var name_label := _label(str(entry.get("name", "")), Vector2(6, 1), Vector2(91, 25), 12, color, chip)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var value := str(entry.get("value", ""))
	if value != "":
		var short_value := value.split(" · ")[0]
		var value_label := _label(short_value, Vector2(91, 2), Vector2(51, 23), 10, GOLD if kind == "buff" else color, chip)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


# ---------- 房间与连击 ----------

func _build_combo(root: Control) -> void:
	_combo_label = _label("", Vector2(460, 108), Vector2(360, 58), 38, VERMILION, root)
	_combo_label.add_theme_color_override("font_outline_color", PAPER)
	_combo_label.add_theme_constant_override("outline_size", 3)
	_combo_label.visible = false


func _build_mode_label(root: Control) -> void:
	_mode_label = _label(_mode_text(), Vector2(340, 44), Vector2(600, 26), 18, INK, root)


func _mode_text() -> String:
	if Run.is_boss_room():
		return "%s · Boss" % Run.mode_label()
	if Run.mode == Run.MODE_ENDLESS:
		return "无尽 · 第 %d 层 · %d/3" % [Run.depth, Run.room_index + 1]
	return "冒险 · %d/3" % [Run.room_index + 1]


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_update_action_bar()
	var current_extra := int(_player.call("hud_extra_hp"))
	if current_extra != _player_extra:
		_player_extra = current_extra
		_hp_bar.set_extra(current_extra)
	if is_instance_valid(_boss) and _boss_bar != null and _boss_bar.visible:
		var boss_extra := int(_boss.call("hud_extra_hp")) if _boss.has_method("hud_extra_hp") else 0
		if boss_extra != _boss_extra:
			_boss_extra = boss_extra
			_boss_vital.set_extra(boss_extra)
	_status_clock -= delta
	if _status_clock <= 0.0:
		_status_clock = 0.20
		_sync_status()


func _on_skull_changed(_id: String) -> void:
	_hud_skills = _player.hud_skills
	_player_extra = int(_player.call("hud_extra_hp"))
	_build_action_bar(_root)
	_sync_status(true)


func _on_hp_changed(hp: int, max_hp: int) -> void:
	if _hp_bar == null:
		return
	_hp_bar.set_vital(hp, max_hp, _player_extra)
	_hp_label.text = "%d/%d" % [hp, max_hp]


func _on_combo_changed(count: int) -> void:
	_combo_label.visible = count >= 2
	_combo_label.text = "%d 连击" % count


# ---------- Boss 大血条 ----------

const BOSS_BAR_W := 440.0
const BOSS_BAR_H := 26.0
var _boss: Node2D = null


func show_boss(boss: Node2D) -> void:
	if _boss_bar == null:
		_build_boss_bar(_root)
	_boss_bar.visible = true
	_boss = boss
	_boss_extra = int(boss.call("hud_extra_hp")) if boss.has_method("hud_extra_hp") else 0
	_boss_name.text = str(boss.get("boss_label"))
	boss.hp_changed.connect(_on_boss_hp_changed)
	boss.died.connect(hide_boss)
	_on_boss_hp_changed(int(boss.get("hp")), int(boss.get("max_hp")))
	_splash_boss_name(_boss_name.text)
	_boss_bar.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_boss_bar, "modulate:a", 1.0, 0.7).set_delay(0.7)


func _splash_boss_name(text: String) -> void:
	var splash := Label.new()
	splash.text = text
	splash.add_theme_font_size_override("font_size", 110)
	splash.add_theme_font_override("font", BOSS_FONT)
	splash.add_theme_color_override("font_color", PAPER)
	splash.add_theme_color_override("font_outline_color", INK)
	splash.add_theme_constant_override("outline_size", 18)
	splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(splash)
	splash.reset_size()
	splash.position = Vector2(640.0 - splash.size.x * 0.5, 190.0)
	splash.pivot_offset = splash.size * 0.5
	splash.scale = Vector2(1.7, 1.7)
	splash.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(splash, "modulate:a", 1.0, 0.22)
	tw.tween_property(splash, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(1.4)
	tw.tween_property(splash, "modulate:a", 0.0, 0.6)
	tw.tween_callback(splash.queue_free)


func hide_boss() -> void:
	if _boss_bar != null:
		_boss_bar.visible = false


func _on_boss_hp_changed(hp: int, max_hp: int) -> void:
	if _boss_vital == null:
		return
	_boss_vital.set_vital(hp, maxi(1, max_hp), _boss_extra)
	if is_instance_valid(_boss) and str(_boss.get("type_id")) == "c001":
		_boss_name.text = "武车 · 耐久 %d/%d" % [hp, max_hp]


func _build_boss_bar(root: Control) -> void:
	_boss_bar = Control.new()
	_boss_bar.position = Vector2(420, 76)
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.visible = false
	root.add_child(_boss_bar)
	_boss_vital = VitalBar.new()
	_boss_vital.bar_width = BOSS_BAR_W
	_boss_vital.bar_height = BOSS_BAR_H
	_boss_vital.extra_width_cap = 78.0
	_boss_bar.add_child(_boss_vital)
	_boss_name = _label("", Vector2.ZERO, Vector2(BOSS_BAR_W, BOSS_BAR_H), 15, PAPER, _boss_bar)
	_boss_name.add_theme_font_override("font", BOSS_FONT)
	_boss_name.add_theme_color_override("font_outline_color", INK)
	_boss_name.add_theme_constant_override("outline_size", 3)
