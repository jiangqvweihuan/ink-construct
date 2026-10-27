extends CanvasLayer

const InkTex = preload("res://scripts/ui/ink_tex.gd")

## 水墨 HUD：左上血条 · 底部技能栏（J 普攻 / 各形态自带的 K L U 技能，带冷却遮罩）
## · 中上连击数 · 右上墨骨计数。技能格数量随换头形态变化，换头时重建。

const BAR_W := 380.0
const BAR_H := 30.0
const SLOT := 48.0 # 技能格边长
const SLOT_GAP := 62.0 # 格间步距
const VERMILION := Color(0.659, 0.196, 0.165) # 朱砂 #A8322A
const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)

var _root: Control
var _action_root: Control
var _hp_clip: Control
var _hp_label: Label
var _combo_label: Label
var _bones_label: Label
var _hud_skills: Array = [] # 当前形态的技能名顺序（与遮罩一一对应）
var _cd_masks: Array = [] # 每个技能格一个冷却遮罩
var _player: Node2D
var _boss_bar: Control
var _boss_clip: Control
var _boss_name: Label


func _rect(tex_path: String, size: Vector2, pos: Vector2, parent: Control) -> TextureRect:
	var t := TextureRect.new()
	t.texture = InkTex.load(tex_path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = size
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
	_build_bones(_root)

	# 先找玩家（技能栏要按当前形态的技能表来建），再建底部动作栏
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		_player.hp_changed.connect(_on_hp_changed)
		_on_hp_changed(_player.hp, _player.max_hp)
		_hud_skills = _player.hud_skills
		_player.skull_changed.connect(_on_skull_changed)
	_build_action_bar(_root)

	Score.combo_changed.connect(_on_combo_changed)
	Score.bones_changed.connect(_on_bones_changed)
	_on_combo_changed(Score.combo)
	_on_bones_changed(Score.bones)


func _build_hp_bar(root: Control) -> void:
	var bar := Control.new()
	bar.position = Vector2(18, 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	_rect("res://art/ui/hud/hp_empty.png", Vector2(BAR_W, BAR_H), Vector2.ZERO, bar)
	_hp_clip = Control.new()
	_hp_clip.clip_contents = true
	_hp_clip.size = Vector2(BAR_W, BAR_H)
	_hp_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_hp_clip)
	var fill := _rect("res://art/ui/hud/bar_white_full.png", Vector2(BAR_W, BAR_H), Vector2.ZERO, _hp_clip)
	fill.modulate = VERMILION
	_rect("res://art/ui/hud/hp_frame.png", Vector2(BAR_W, BAR_H), Vector2.ZERO, bar)
	_hp_label = Label.new()
	_hp_label.position = Vector2(12, 5)
	_hp_label.add_theme_color_override("font_color", PAPER)
	_hp_label.add_theme_font_size_override("font_size", 15)
	bar.add_child(_hp_label)


func _build_action_bar(root: Control) -> void:
	# 换头会换技能表，整条栏重建；旧栏先拆掉
	if _action_root != null and is_instance_valid(_action_root):
		_action_root.queue_free()
	_action_root = Control.new()
	_action_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_action_root)
	_cd_masks.clear()

	var splat := _rect("res://art/ui/hud/action_splat.png", Vector2(300, 92), Vector2(490, 636), _action_root)
	splat.modulate = Color(1, 1, 1, 0.92)
	# 第一格 J 是普攻（无冷却），后面按当前形态的技能表依次排
	var slot_count: int = 1 + _hud_skills.size()
	var total_w := SLOT_GAP * float(slot_count - 1) + SLOT
	var start_x := 640.0 - total_w * 0.5
	for i in slot_count:
		var x := start_x + i * SLOT_GAP
		_rect("res://art/ui/hud/skill_slot.png", Vector2(SLOT, SLOT), Vector2(x, 658), _action_root)
		var key := "J"
		if i > 0 and _player != null and is_instance_valid(_player):
			key = _player.get_skill_key(str(_hud_skills[i - 1]))
		var l := Label.new()
		l.text = key
		l.size = Vector2(SLOT, SLOT)
		l.position = Vector2(x, 660)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", PAPER)
		l.add_theme_font_size_override("font_size", 20)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_action_root.add_child(l)
		# J 普攻无冷却，遮罩位留 null；技能格各配一个从下往上收缩的黑罩
		if i == 0:
			_cd_masks.append(null)
			continue
		var mask := ColorRect.new()
		mask.color = Color(0.05, 0.05, 0.05, 0.62)
		mask.position = Vector2(x, 658)
		mask.size = Vector2(SLOT, 0)
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mask.visible = false
		_action_root.add_child(mask)
		_cd_masks.append(mask)


func _build_combo(root: Control) -> void:
	_combo_label = Label.new()
	_combo_label.size = Vector2(360, 70)
	_combo_label.position = Vector2(460, 92) # 屏幕上方居中
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_combo_label.add_theme_color_override("font_color", VERMILION)
	_combo_label.add_theme_font_size_override("font_size", 40)
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_label.visible = false
	root.add_child(_combo_label)


func _build_bones(root: Control) -> void:
	_bones_label = Label.new()
	_bones_label.size = Vector2(200, 36)
	_bones_label.position = Vector2(1050, 14) # 右上角
	_bones_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bones_label.add_theme_color_override("font_color", INK)
	_bones_label.add_theme_font_size_override("font_size", 22)
	_bones_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bones_label)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# 技能格冷却：遮罩从满格高度按比例缩小，直观显示"还剩多久"
	for i in _hud_skills.size():
		if i + 1 >= _cd_masks.size():
			break
		var mask: ColorRect = _cd_masks[i + 1]
		if mask == null:
			continue
		var ratio: float = _player.get_skill_cd_ratio(str(_hud_skills[i]))
		if ratio <= 0.001:
			mask.visible = false
			continue
		mask.visible = true
		var h := SLOT * ratio
		mask.size.y = h
		mask.position.y = 658.0 + (SLOT - h) # 贴在格底往上生长


func _on_skull_changed(_id: String) -> void:
	_hud_skills = _player.hud_skills
	_build_action_bar(_root)


func _on_hp_changed(hp: int, max_hp: int) -> void:
	_hp_clip.size.x = BAR_W * clampf(float(hp) / float(max_hp), 0.0, 1.0)
	_hp_label.text = "%d/%d" % [hp, max_hp]


func _on_combo_changed(count: int) -> void:
	# 1 连击不值得庆祝，从 2 开始显示
	_combo_label.visible = count >= 2
	_combo_label.text = "%d 连击" % count


func _on_bones_changed(count: int) -> void:
	_bones_label.text = "墨骨  %d" % count


# ---------- Boss 大血条（顶部居中，Boss 房专属） ----------

const BOSS_BAR_W := 480.0
const BOSS_BAR_H := 26.0


## Boss 登场时由房间调用：亮出血条并挂信号
func show_boss(boss: Node2D) -> void:
	if _boss_bar == null:
		_build_boss_bar(_root)
	_boss_bar.visible = true
	_boss_name.text = str(boss.get("boss_label"))
	boss.hp_changed.connect(_on_boss_hp_changed)
	boss.died.connect(hide_boss)
	_on_boss_hp_changed(int(boss.get("hp")), int(boss.get("max_hp")))


func hide_boss() -> void:
	if _boss_bar != null:
		_boss_bar.visible = false


func _on_boss_hp_changed(hp: int, max_hp: int) -> void:
	if _boss_clip == null:
		return
	_boss_clip.size.x = BOSS_BAR_W * clampf(float(hp) / float(max_hp), 0.0, 1.0)


func _build_boss_bar(root: Control) -> void:
	_boss_bar = Control.new()
	_boss_bar.position = Vector2(400, 14) # 顶部居中偏右，避开左上玩家血条
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.visible = false
	root.add_child(_boss_bar)
	_rect("res://art/ui/hud/hp_empty.png", Vector2(BOSS_BAR_W, BOSS_BAR_H), Vector2.ZERO, _boss_bar)
	_boss_clip = Control.new()
	_boss_clip.clip_contents = true
	_boss_clip.size = Vector2(BOSS_BAR_W, BOSS_BAR_H)
	_boss_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.add_child(_boss_clip)
	var fill := _rect("res://art/ui/hud/bar_white_full.png", Vector2(BOSS_BAR_W, BOSS_BAR_H), Vector2.ZERO, _boss_clip)
	fill.modulate = VERMILION
	_rect("res://art/ui/hud/hp_frame.png", Vector2(BOSS_BAR_W, BOSS_BAR_H), Vector2.ZERO, _boss_bar)
	_boss_name = Label.new()
	_boss_name.size = Vector2(BOSS_BAR_W, BOSS_BAR_H)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boss_name.add_theme_color_override("font_color", PAPER)
	_boss_name.add_theme_font_size_override("font_size", 15)
	_boss_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.add_child(_boss_name)
