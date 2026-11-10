extends CanvasLayer

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Settings = preload("res://scripts/ui/settings.gd")
const LocalCoop = preload("res://scripts/systems/local_coop.gd")
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
var _player: Node2D
## 本机可控角色（本机双人时 P1/P2 都在本机；联机时只有自己那一位）
var _local_players: Array = []
## 每位本机角色的技能栏：player / skills / masks / cd_labels / lock_labels / y
var _bars: Array = []
var _player_extra := 0
var _partner: Node2D # 第一位队友（slot 1），保留兼容；主 HUD 只显示本机角色
var _partner_bar: Control
var _partner_extra := 0
## 联机 4 人：slot 2/3 的队友血条与额外生命缓存
var _extra_partner_bars: Dictionary = {} # slot -> Control
var _extra_partner_extra: Dictionary = {} # slot -> int
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
	_local_players = _collect_local_players(players)
	if not _local_players.is_empty():
		# 本机双人两位都归本机；联机客机只认自己槽位，主机只认 P1
		_player = _local_players[0]
		_player.hp_changed.connect(_on_hp_changed)
		_player_extra = int(_player.call("hud_extra_hp"))
		_on_hp_changed(_player.hp, _player.max_hp)
		_hud_skills = _player.hud_skills
	_build_action_bar(_root)
	_build_partner_bar(_root, players)
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


## 多人：右上角按槽位给每位队友补一条生命条（最多 3 条纵向排列）
func _build_partner_bar(root: Control, players: Array) -> void:
	var others: Array = []
	for p in players:
		if is_instance_valid(p) and p != _player and int(p.get("input_slot")) > 0:
			others.append(p)
	others.sort_custom(func(a, b): return int(a.get("input_slot")) < int(b.get("input_slot")))
	for i in others.size():
		var p = others[i]
		var slot := int(p.get("input_slot"))
		var box := Control.new()
		box.position = Vector2(998, 14 + i * 38)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(box)
		var tag := _label("P%d" % (slot + 1), Vector2(0, 4), Vector2(34, 24), 17, PAPER, box)
		tag.add_theme_color_override("font_outline_color", INK)
		tag.add_theme_constant_override("outline_size", 4)
		var bar := VitalBar.new()
		bar.bar_width = 226.0
		bar.bar_height = 22.0
		bar.position = Vector2(42, 6)
		box.add_child(bar)
		if i == 0:
			_partner = p
			_partner_bar = bar
			_partner_extra = int(p.call("hud_extra_hp"))
			p.hp_changed.connect(_on_partner_hp_changed.bind(slot))
			_on_partner_hp_changed(p.hp, p.max_hp, slot)
		else:
			_extra_partner_bars[slot] = bar
			_extra_partner_extra[slot] = int(p.call("hud_extra_hp"))
			p.hp_changed.connect(_on_partner_hp_changed.bind(slot))


func _on_partner_hp_changed(hp: int, max_hp: int, slot := 1) -> void:
	if slot == 1:
		if _partner_bar != null:
			_partner_bar.set_vital(hp, max_hp, _partner_extra)
		return
	if _extra_partner_bars.has(slot):
		_extra_partner_bars[slot].set_vital(hp, max_hp, int(_extra_partner_extra.get(slot, 0)))


# ---------- 底部动作栏 ----------

## 本机可控角色：本机双人 = 两位；联机客机 = 自己槽位；联机主机/单人 = P1。
func _collect_local_players(players: Array) -> Array:
	var out: Array = []
	for p in players:
		if not is_instance_valid(p):
			continue
		var slot := int(p.get("input_slot"))
		var local := true
		if Run.net_role == "client":
			local = slot == Run.net_slot
		elif Run.net_role == "host":
			local = slot == 0
		if local:
			out.append(p)
	out.sort_custom(func(a, b): return int(a.get("input_slot")) < int(b.get("input_slot")))
	if out.is_empty() and not players.is_empty():
		out.append(players[0])
	return out


## 底部技能栏：每位本机角色一条，左半 P1、右半 P2，图标 / 冷却 / 招式名完全独立。
func _build_action_bar(root: Control) -> void:
	if _action_root != null and is_instance_valid(_action_root):
		_action_root.queue_free()
	_action_root = Control.new()
	_action_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_action_root)
	_bars.clear()
	if _local_players.is_empty():
		return
	# 窄画布（4:3）逻辑宽度不足 1280，按实际宽度分配左右半区，避免 P2 栏被裁掉
	var usable := minf(1280.0, get_viewport().get_visible_rect().size.x)
	var count := _local_players.size()
	for i in count:
		var p = _local_players[i]
		if not is_instance_valid(p):
			continue
		var half := usable / float(count)
		var cx := usable * 0.5 if count <= 1 else half * (i + 0.5)
		_build_one_bar(p, cx, half)
		if not p.skull_changed.is_connected(_on_skull_changed):
			p.skull_changed.connect(_on_skull_changed)


func _build_one_bar(p: Node2D, cx: float, half: float) -> void:
	var skills: Array = p.hud_skills
	var slot_count: int = 1 + skills.size()
	var gap := SLOT_GAP if slot_count <= 6 else 60.0
	# 半区放不下时压缩间距，保证 FHD / 4:3 下都不会越过中线和屏幕边缘
	var max_w := half - 24.0
	if slot_count > 1 and gap * float(slot_count - 1) + SLOT > max_w:
		gap = maxf(44.0, (max_w - SLOT) / float(slot_count - 1))
	var total_w := gap * float(slot_count - 1) + SLOT
	var splat_w := clampf(total_w + 100.0, 300.0, half - 8.0)
	var splat := _rect("res://art/ui/hud/action_splat.png", Vector2(splat_w, 104), Vector2(cx - splat_w * 0.5, 624), _action_root)
	splat.modulate = Color(1, 1, 1, 0.94)
	var start_x := cx - total_w * 0.5
	var y := 650.0
	# P1 / P2 标识：双人时一眼分清左右两条技能栏归谁
	if _local_players.size() > 1:
		var tag := _label("P%d" % (int(p.get("input_slot")) + 1), Vector2(cx - 30, y - 50), Vector2(60, 22), 14, GOLD, _action_root)
		tag.add_theme_color_override("font_outline_color", INK)
		tag.add_theme_constant_override("outline_size", 4)
	var masks: Array = []
	var cds: Array = []
	var locks: Array = []
	for i in slot_count:
		var x := start_x + i * gap
		var skill_id := "" if i == 0 else str(skills[i - 1])
		var title := "普攻" if i == 0 else BattleStatus.skill_name(p, i - 1)
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
		masks.append(mask)
		var key := ""
		if i == 0:
			# 只有本机双人的 P2 用 1 键；联机客机虽然占 1 号槽，用的仍是自己设备的 P1 设置键
			key = LocalCoop.key_label("attack") if (int(p.get("input_slot")) != 0 and Run.net_role == "") else Settings.action_label("attack")
		else:
			key = str(p.get_skill_key(skill_id))
		if TouchControls.active:
			key = "攻" if i == 0 else "墨" # 移动端没有键盘，改成手势标识
		var key_label := _label(key, Vector2(x, y + 3), Vector2(SLOT, SLOT - 6), 23, PAPER, _action_root)
		key_label.add_theme_color_override("font_outline_color", INK)
		key_label.add_theme_constant_override("outline_size", 3)
		var cd_label := _label("", Vector2(x, y + 3), Vector2(SLOT, SLOT - 6), 20, PAPER, _action_root)
		cd_label.add_theme_color_override("font_outline_color", INK)
		cd_label.add_theme_constant_override("outline_size", 5)
		cd_label.visible = false
		cds.append(cd_label)
		var lock := _label("", Vector2(x - 4, y + SLOT - 17), Vector2(SLOT + 8, 18), 11, Color(1.0, 0.55, 0.42), _action_root)
		lock.add_theme_color_override("font_outline_color", INK)
		lock.add_theme_constant_override("outline_size", 3)
		lock.visible = false
		locks.append(lock)
	_bars.append({"player": p, "skills": skills, "masks": masks, "cds": cds, "locks": locks, "y": y})


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
	# 每位本机角色各读各的技能冷却，P1/P2 互不影响
	for bar in _bars:
		var p = bar["player"]
		if p == null or not is_instance_valid(p):
			continue
		var skills: Array = bar["skills"]
		var y := float(bar["y"])
		var masks: Array = bar["masks"]
		var cds: Array = bar["cds"]
		var locks: Array = bar["locks"]
		for i in skills.size():
			if i + 1 >= masks.size():
				break
			var skill_id := str(skills[i])
			var ratio: float = p.get_skill_cd_ratio(skill_id)
			var left := BattleStatus.skill_cooldown(p, skill_id)
			var mask: ColorRect = masks[i + 1]
			var cd_label: Label = cds[i + 1]
			mask.visible = ratio > 0.001
			cd_label.visible = left > 0.05
			if mask.visible:
				var h := (SLOT - 6) * ratio
				mask.size.y = h
				mask.position.y = y + 3.0 + (SLOT - 6 - h)
			if cd_label.visible:
				cd_label.text = "%.1f" % left if left < 3.0 else str(int(ceil(left)))
			var lock_text := BattleStatus.skill_lock(p, skill_id) if ratio <= 0.001 else ""
			var lock_label: Label = locks[i + 1]
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
	if is_instance_valid(_partner) and _partner_bar != null:
		var partner_extra := int(_partner.call("hud_extra_hp"))
		if partner_extra != _partner_extra:
			_partner_extra = partner_extra
			_partner_bar.set_extra(partner_extra)
	_status_clock -= delta
	if _status_clock <= 0.0:
		_status_clock = 0.20
		_sync_status()


func _on_skull_changed(_id: String) -> void:
	# 任意一位本机角色换化身都要重排双栏，避免 P2 的招式还停留在旧角色
	if _player != null and is_instance_valid(_player):
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
