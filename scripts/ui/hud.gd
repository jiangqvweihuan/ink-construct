extends CanvasLayer

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Settings = preload("res://scripts/ui/settings.gd")
const VitalBar = preload("res://scripts/ui/vital_bar.gd")
const BattleStatus = preload("res://scripts/ui/battle_status.gd")

## 水墨 HUD：多层生命条、生命条下方的状态印记、底部带招式名与数值冷却的技能栏。

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
const STATUS_ICON := 30.0
const STATUS_GAP := 6.0
const STATUS_PER_ROW := 9

var _root: Control
var _action_root: Control
var _hp_bar: Control
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
var _status_strip: Control
var _status_icons: Dictionary = {}
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
	# 手机超宽画布下把整层右移，保持 1280 版面的视觉居中
	UiKit.fit_layer(self)
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
	get_viewport().size_changed.connect(_on_view_resized)


## 画布比例变化（转屏/切换窗口）时重新居中，并重排底部动作栏
func _on_view_resized() -> void:
	UiKit.fit_layer(self)
	_build_action_bar(_root)


func _build_hp_bar(root: Control) -> void:
	var bar := Control.new()
	bar.position = Vector2(18, 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	_hp_bar = VitalBar.new()
	_hp_bar.bar_width = BAR_W
	_hp_bar.bar_height = BAR_H
	bar.add_child(_hp_bar)


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
	var cx := 640.0 # 1280 基准画布中心；超宽画布由 CanvasLayer.offset 整层居中
	var splat := _rect("res://art/ui/hud/action_splat.png", Vector2(splat_w, 104), Vector2(cx - splat_w * 0.5, 624), _action_root)
	splat.modulate = Color(1, 1, 1, 0.94)
	var start_x := cx - total_w * 0.5
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
		if TouchControls.active:
			key = "攻" if i == 0 else "墨" # 移动端没有键盘，改成手势标识
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


# ---------- 生命条下方状态印记 ----------

## 战斗内的增益/减益只以「印章」形式显示在生命条下方：
## 单字圆印 + 种类描边，详情悬停查看，暂停菜单可读全文。
## 计时类在最后 3 秒轻微呼吸，堆叠类右下角显示层数。
func _build_status(root: Control) -> void:
	_status_strip = Control.new()
	_status_strip.position = Vector2(20, 50)
	_status_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_strip.visible = false
	root.add_child(_status_strip)


func _sync_status(force := false) -> void:
	if _status_strip == null or _player == null or not is_instance_valid(_player):
		return
	var shown: Array = []
	for entry in BattleStatus.entries(_player):
		var kind := str(entry.get("kind", ""))
		if kind == "buff" or kind == "debuff":
			shown.append(entry)
	var ids: Array = []
	for entry in shown:
		ids.append("%s:%s:%s" % [
			str(entry.get("id", entry.get("name", ""))),
			str(entry.get("kind", "")),
			str(entry.get("name", "")),
		])
	var signature := "|".join(ids)
	if force or signature != _status_signature:
		_status_signature = signature
		_rebuild_status_icons(shown)
	_update_status_icons(shown)
	_status_strip.visible = not shown.is_empty()


func _rebuild_status_icons(shown: Array) -> void:
	for child in _status_strip.get_children():
		_status_strip.remove_child(child)
		child.queue_free()
	_status_icons.clear()
	for i in mini(shown.size(), STATUS_PER_ROW * 2):
		var entry: Dictionary = shown[i]
		var col := i % STATUS_PER_ROW
		var row := floori(i / float(STATUS_PER_ROW))
		var pos := Vector2(col * (STATUS_ICON + STATUS_GAP), row * (STATUS_ICON + STATUS_GAP))
		var icon := _make_status_icon(entry, pos)
		_status_icons[str(entry.get("id", entry.get("name", i)))] = icon


func _make_status_icon(entry: Dictionary, pos: Vector2) -> Dictionary:
	var kind := str(entry.get("kind", "buff"))
	var is_debuff := kind == "debuff"
	var accent := Color(1.0, 0.60, 0.52) if is_debuff else GOLD
	var root := Control.new()
	root.position = pos
	root.size = Vector2(STATUS_ICON, STATUS_ICON)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.tooltip_text = _status_tooltip(entry)
	_status_strip.add_child(root)

	var seal := Panel.new()
	seal.position = Vector2.ZERO
	seal.size = Vector2(STATUS_ICON, STATUS_ICON)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.032, 0.028, 0.78)
	sb.set_corner_radius_all(int(STATUS_ICON * 0.5))
	sb.set_border_width_all(1)
	sb.border_color = Color(accent, 0.86)
	sb.shadow_color = Color(accent, 0.20)
	sb.shadow_size = 4
	seal.add_theme_stylebox_override("panel", sb)
	root.add_child(seal)

	var raw_name := str(entry.get("name", "")).strip_edges()
	var glyph := raw_name.substr(0, 1) if raw_name != "" else "·"
	var glyph_label := _label(glyph, Vector2.ZERO, Vector2(STATUS_ICON, STATUS_ICON), 16, accent, root)
	glyph_label.add_theme_color_override("font_outline_color", INK)
	glyph_label.add_theme_constant_override("outline_size", 3)

	var badge := _label("", Vector2(0, STATUS_ICON - 14), Vector2(STATUS_ICON - 3, 12), 9, accent, root)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.add_theme_color_override("font_outline_color", INK)
	badge.add_theme_constant_override("outline_size", 3)
	return {"root": root, "badge": badge}


func _update_status_icons(shown: Array) -> void:
	for entry in shown:
		var key := str(entry.get("id", entry.get("name", "")))
		if not _status_icons.has(key):
			continue
		var icon: Dictionary = _status_icons[key]
		var root: Control = icon["root"]
		var badge: Label = icon["badge"]
		if not is_instance_valid(root):
			continue
		root.tooltip_text = _status_tooltip(entry)
		var value := str(entry.get("value", ""))
		var stacks := _entry_stacks(value)
		badge.text = ("×%d" % stacks) if stacks > 1 else ""
		var secs := _entry_seconds(value)
		# 最后 3 秒逐渐变淡；比闪烁更克制，也不会和画面里的高光抢注意力。
		root.modulate.a = 1.0
		if secs >= 0.0 and secs <= 3.0:
			root.modulate.a = 0.55 + 0.45 * clampf(secs / 3.0, 0.0, 1.0)


func _status_tooltip(entry: Dictionary) -> String:
	var name := str(entry.get("name", "")).strip_edges()
	var value := str(entry.get("value", "")).strip_edges()
	var desc := str(entry.get("desc", "")).strip_edges()
	if value != "":
		name += "  " + value
	if desc != "":
		name += "\n" + desc
	return name


func _entry_seconds(value: String) -> float:
	var idx := value.find("秒")
	if idx <= 0:
		return -1.0
	var tokens := value.substr(0, idx).strip_edges().split(" ", false)
	if tokens.is_empty():
		return -1.0
	var last := str(tokens[tokens.size() - 1]).strip_edges()
	return float(last) if last.is_valid_float() else -1.0


func _entry_stacks(value: String) -> int:
	var idx := value.find("层")
	if idx <= 0:
		return 0
	var tokens := value.substr(0, idx).strip_edges().split(" ", false)
	if tokens.is_empty():
		return 0
	var last := str(tokens[tokens.size() - 1])
	if last.is_valid_int():
		return int(last)
	for part in last.split("／"):
		if str(part).is_valid_int():
			return int(part)
	return 0


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
