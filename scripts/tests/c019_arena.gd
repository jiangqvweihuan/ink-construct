extends Node2D

## 剑冢双形态 Boss 专属机制测试场。
## 独立运行，不经过关卡、波次、Boss 房前流程；进入即与 C019 一阶段开战。
##
## 调试键位：
##   R  重置整场战斗（重新生成玩家与一阶段剑冢）
##   H  把当前 Boss 压到 1 点生命，便于下一击触发换形 / 斩杀
##   T  一阶段强制触发换形演出（二阶段不可用）
## 玩家：初始 9999 生命、技能零冷却、闪避零冷却；Boss 数值 / 判定 / 碰撞 / 场地边界均沿用正式配置。

const C019Script = preload("res://scripts/enemies/c019.gd")
const C016Class = preload("res://scripts/enemies/c016.gd")
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const BOSS_SCENE := "res://scenes/enemies/bosses/boss.tscn"
const PLAYER_SKULL := "c021"

const ROOM_W := 1920.0
const GROUND_Y := 640.0
const SPAWN_Y := 560.0
const PLAYER_X := 460.0
const BOSS_X := 1120.0
const GOD_HP := 9999
const DEBUG_PANEL_W := 440.0
const DEBUG_PANEL_H := 270.0
const HP_BAR_W := 360.0
const HP_BAR_H := 22.0

const MOVE_NAMES := {
	"p1_thrust": "断岳飞锋",
	"p1_rain": "飞锋三叠",
	"p1_sweep": "拂尘剑幕",
	"p1_ring": "回锋阵",
	"p2_flash": "焚锋一闪",
	"p2_rain": "万刃归冢",
	"p2_prison": "剑狱天倾",
	"p2_combo": "冢前百刃",
}

const STATE_NAMES := {
	0: "待机", 1: "巡逻", 2: "追击", 3: "出手", 4: "受击", 5: "死亡", 6: "浮空",
	100: "登场", 101: "换形演出", 102: "僵直", 103: "冲锋蓄力", 104: "冲锋", 105: "转身",
}

var _player
var _boss
var _camera: Camera2D
var _debug: RichTextLabel
var _note: Label
var _hp_label: Label
var _hp_fill: ColorRect
var _boss_dead := false
var _was_phase_two := false
var _reset_pending := false


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	Run.start(Run.MODE_ADVENTURE, PLAYER_SKULL, 1)
	Run.balance_scaling = false # 固定基础数值：Boss 伤害 / 血量 / 冷却不随人数缩放
	set_meta("battle_width", ROOM_W)
	_build_arena()
	_build_ui()
	_spawn_player()
	_spawn_boss()


# ---------- 场景搭建 ----------

func _build_arena() -> void:
	# 与正式 Boss 房一致：使用墨堂深处背景，画中地面线对齐 GROUND_Y
	var boss_bg := load("res://art/environment/background/bg_boss.png") as Texture2D
	if boss_bg != null:
		var bg_sprite := Sprite2D.new()
		bg_sprite.texture = boss_bg
		bg_sprite.centered = false
		bg_sprite.scale = Vector2(1.25, 1.25) # 1536x768 -> 1920x960
		bg_sprite.position = Vector2(0.0, GROUND_Y - 704.0 * 1.25)
		bg_sprite.z_index = -20
		add_child(bg_sprite)
	else:
		var paper := ColorRect.new()
		paper.color = Color(0.949, 0.918, 0.847)
		paper.size = Vector2(ROOM_W, 720.0)
		paper.z_index = -20
		paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(paper)
		var ground_visual := ColorRect.new()
		ground_visual.color = Color(0.14, 0.13, 0.12)
		ground_visual.size = Vector2(ROOM_W, 80.0)
		ground_visual.position = Vector2(0.0, GROUND_Y)
		ground_visual.z_index = -10
		ground_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ground_visual)

	# 地面碰撞顶面 = GROUND_Y，与正式房间一致
	var ground := StaticBody2D.new()
	ground.position = Vector2(ROOM_W * 0.5, GROUND_Y + 40.0)
	add_child(ground)
	var ground_shape := CollisionShape2D.new()
	var ground_rect := RectangleShape2D.new()
	ground_rect.size = Vector2(ROOM_W, 80.0)
	ground_shape.shape = ground_rect
	ground.add_child(ground_shape)

	# 左右围墙与正式房间同一位置，保留原场地边界
	for x in [-20.0, ROOM_W + 20.0]:
		var wall := StaticBody2D.new()
		wall.position = Vector2(x, 360.0)
		add_child(wall)
		var wall_shape := CollisionShape2D.new()
		var wall_rect := RectangleShape2D.new()
		wall_rect.size = Vector2(40.0, 720.0)
		wall_shape.shape = wall_rect
		wall.add_child(wall_shape)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)

	var panel := ColorRect.new()
	panel.color = Color(0.03, 0.03, 0.03, 0.82)
	panel.position = Vector2(16.0, 16.0)
	panel.size = Vector2(DEBUG_PANEL_W, DEBUG_PANEL_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)

	_debug = RichTextLabel.new()
	_debug.bbcode_enabled = true
	_debug.scroll_active = false
	_debug.position = Vector2(28.0, 24.0)
	_debug.size = Vector2(DEBUG_PANEL_W - 24.0, DEBUG_PANEL_H - 58.0)
	_debug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug.add_theme_font_size_override("normal_font_size", 13)
	_debug.add_theme_color_override("default_color", Color(0.91, 0.88, 0.79))
	layer.add_child(_debug)

	# Boss 血条加一层深色底，避免纸白背景下白字看不清
	var hp_panel := ColorRect.new()
	hp_panel.color = Color(0.03, 0.03, 0.03, 0.78)
	hp_panel.position = Vector2(462.0, 0.0)
	hp_panel.size = Vector2(376.0, 50.0)
	hp_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hp_panel)

	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0.12, 0.11, 0.10, 0.9)
	hp_bg.position = Vector2(470.0, 24.0)
	hp_bg.size = Vector2(HP_BAR_W, HP_BAR_H)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hp_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.66, 0.2, 0.16)
	_hp_fill.position = Vector2(470.0, 24.0)
	_hp_fill.size = Vector2(HP_BAR_W, HP_BAR_H)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hp_fill)

	_hp_label = Label.new()
	_hp_label.position = Vector2(470.0, 2.0)
	_hp_label.size = Vector2(560.0, 20.0)
	_hp_label.add_theme_font_size_override("font_size", 15)
	_hp_label.add_theme_color_override("font_color", Color(0.949, 0.918, 0.847))
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hp_label)

	var note_bg := ColorRect.new()
	note_bg.color = Color(0.03, 0.03, 0.03, 0.72)
	note_bg.position = Vector2(462.0, 50.0)
	note_bg.size = Vector2(560.0, 26.0)
	note_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(note_bg)

	_note = Label.new()
	_note.position = Vector2(470.0, 53.0)
	_note.size = Vector2(620.0, 22.0)
	_note.add_theme_font_size_override("font_size", 14)
	_note.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.text = "战斗开始 · 一阶段"
	layer.add_child(_note)

	_make_debug_button(layer, "重置战斗 [R]", Vector2(16.0, 294.0), Vector2(130.0, 36.0), _reset_fight)
	_make_debug_button(layer, "压 1 血 [H]", Vector2(152.0, 294.0), Vector2(130.0, 36.0), _drop_boss_low)
	_make_debug_button(layer, "强制换形 [T]", Vector2(288.0, 294.0), Vector2(150.0, 36.0), _force_phase_two)
	_make_debug_button(layer, "二阶段半血 [G]", Vector2(16.0, 336.0), Vector2(150.0, 36.0), _drop_boss_half)

	var hint_bg := ColorRect.new()
	hint_bg.color = Color(0.03, 0.03, 0.03, 0.55)
	hint_bg.position = Vector2(0.0, 684.0)
	hint_bg.size = Vector2(1280.0, 36.0)
	hint_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hint_bg)

	var hint := Label.new()
	hint.position = Vector2(0.0, 692.0)
	hint.size = Vector2(1280.0, 22.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.82, 0.78, 0.69))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.text = "玩家 9999 生命 · 技能零冷却 · Boss 数值/判定/碰撞/边界沿用正式配置"
	layer.add_child(hint)


func _make_debug_button(layer: CanvasLayer, text: String, pos: Vector2, size: Vector2, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.size = size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(callback)
	layer.add_child(button)


# ---------- 角色 / Boss ----------

func _spawn_player() -> void:
	var player = load(PLAYER_SCENE).instantiate()
	player.input_slot = 0
	player.position = Vector2(PLAYER_X, SPAWN_Y)
	add_child(player)
	Run.apply_to(player)
	player.max_hp = GOD_HP
	player.hp = GOD_HP
	player.cooldown_scale = 0.0
	player.dash_cooldown = 0.0
	player.hp_changed.emit(player.hp, player.max_hp)
	player.died.connect(_on_player_died)
	_player = player

	var cam := Camera2D.new()
	cam.position = Vector2(0.0, -80.0)
	cam.limit_left = 0
	cam.limit_right = int(ROOM_W)
	cam.limit_top = 0
	cam.limit_bottom = 720
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	player.add_child(cam)
	cam.make_current()
	Feel.register_camera(cam)
	_camera = cam


func _spawn_boss() -> void:
	var boss = load(BOSS_SCENE).instantiate()
	boss.set_script(C019Script)
	boss.type_id = "c019"
	boss.hp_scale = 1.0
	boss.cd_scale = 1.0
	boss.position = Vector2(BOSS_X, SPAWN_Y)
	boss.died.connect(_on_boss_died)
	add_child(boss)
	_boss = boss
	_boss_dead = false
	_was_phase_two = false
	_note.text = "战斗开始 · 一阶段"


# ---------- 调试操作 ----------

func _reset_fight() -> void:
	_reset_pending = false
	if is_instance_valid(_boss):
		if C016Class._attacker == _boss:
			C016Class._attacker = null
		_boss.queue_free()
	_boss = null
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null
	C016Class._attacker = null
	C016Class._token_free_at = 0
	_boss_dead = false
	_was_phase_two = false
	_spawn_player()
	_spawn_boss()
	_note.text = "战斗已重置 · 一阶段"


func _drop_boss_low() -> void:
	if not is_instance_valid(_boss) or _boss_dead:
		return
	var max_hp := maxi(1, int(_boss.max_hp))
	var low := mini(1, max_hp)
	if int(_boss.hp) <= low:
		return
	_boss.hp = low
	_boss.hp_changed.emit(low, max_hp)
	_note.text = "Boss 已压至 1 血 · 下一击可触发换形/斩杀"


func _drop_boss_half() -> void:
	if not is_instance_valid(_boss) or _boss_dead:
		return
	if not bool(_boss.get("_phase_two")):
		_note.text = "一阶段没有半血机制；可先按 T 换形"
		return
	var max_hp := maxi(1, int(_boss.max_hp))
	var half := maxi(1, int(ceil(float(max_hp) * 0.5)))
	if int(_boss.hp) <= half:
		return
	_boss.hp = half
	_boss.hp_changed.emit(half, max_hp)
	_note.text = "已压至半血 · 下一击触发万刃同悲"


func _force_phase_two() -> void:
	if not is_instance_valid(_boss) or _boss_dead:
		return
	if bool(_boss.get("_phase_two")):
		_note.text = "当前已是二阶段"
		return
	if bool(_boss.get("_invincible")) or int(_boss.state) == 101:
		_note.text = "换形演出中，请稍候"
		return
	_boss.take_damage(9999, _boss.global_position.x + 1.0)
	_note.text = "已强制触发换形"


func _on_boss_died() -> void:
	_boss_dead = true
	_note.text = "Boss 已被击败 · 按 R 重置"


func _on_player_died() -> void:
	if _reset_pending:
		return
	_reset_pending = true
	_note.text = "玩家阵亡 · 1 秒后自动重置"
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree() or not _reset_pending:
		return # 等待期间玩家已手动重置：不要二次清场
	_reset_fight()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_R:
			_reset_fight()
		KEY_H:
			_drop_boss_low()
		KEY_T:
			_force_phase_two()
		KEY_G:
			_drop_boss_half()


# ---------- 调试面板 ----------

func _process(_delta: float) -> void:
	_update_debug()


func _update_debug() -> void:
	var player_line := "玩家 —"
	if is_instance_valid(_player):
		player_line = "玩家  %d / %d   （零冷却）" % [int(_player.hp), int(_player.max_hp)]

	var lines: Array = []
	var hp := 0
	var max_hp := 0
	if not is_instance_valid(_boss):
		_hp_label.text = "剑冢  —"
		_hp_fill.size = Vector2(0.0, HP_BAR_H)
		_debug.text = "[b]剑冢[/b]\nBoss 未生成\n\n" + player_line
		return

	var phase_two := bool(_boss.get("_phase_two"))
	var label := str(_boss.get("boss_label"))
	if label.is_empty():
		label = "剑冢"
	if _boss_dead:
		_hp_label.text = "%s  —" % label
		_hp_fill.size = Vector2(0.0, HP_BAR_H)
		lines.append("[b]%s[/b]" % label)
		lines.append("已击败 · 按 R 重置战斗")
		lines.append("")
		lines.append(player_line)
		_debug.text = "\n".join(lines)
		return

	max_hp = maxi(1, int(_boss.max_hp))
	hp = clampi(int(_boss.hp), 0, max_hp)
	_hp_label.text = "%s  %d / %d" % [label, hp, max_hp]
	_hp_fill.size = Vector2(HP_BAR_W * float(hp) / float(max_hp), HP_BAR_H)
	_hp_fill.color = Color(0.78, 0.62, 0.25) if phase_two else Color(0.66, 0.2, 0.16)

	if phase_two and not _was_phase_two:
		_was_phase_two = true
		_note.text = "已进入二阶段 · 剑冢·万刃"

	var phase := "二阶段" if phase_two else "一阶段"
	var state_name := str(STATE_NAMES.get(int(_boss.state), str(_boss.state)))
	var invincible := "是" if bool(_boss.get("_invincible")) else "否"
	var passive := "剑势 %d / 2" % int(_boss.get("_p1_marks"))
	if phase_two:
		passive = "万刃同悲 " + ("已触发" if bool(_boss.get("_phase2_enraged")) else "未触发")

	var cds: Dictionary = _boss._attack_rule_cds
	var cd_lines: Array = []
	for move in _boss._attack_anims:
		var key := str(move)
		var cd := maxf(0.0, float(cds.get(key, 0.0)))
		var cd_text := "就绪" if cd <= 0.001 else "%.1fs" % cd
		cd_lines.append("  %s  %s" % [str(MOVE_NAMES.get(key, key)), cd_text])

	lines.append("[b]%s · %s[/b]" % [label, phase])
	lines.append("生命  %d / %d" % [hp, max_hp])
	lines.append("状态  %s    无敌  %s" % [state_name, invincible])
	lines.append(passive)
	lines.append("下次起手  %.1fs    出手间隔  %.1fs    移速  %.0f" % [
		maxf(0.0, float(_boss._attack_cd)), float(_boss.attack_cooldown), float(_boss.chase_speed)])
	lines.append("招式冷却：")
	for line in cd_lines:
		lines.append(str(line))
	lines.append(player_line)
	_debug.text = "\n".join(lines)


func _exit_tree() -> void:
	if is_instance_valid(_boss) and C016Class._attacker == _boss:
		C016Class._attacker = null
	C016Class._token_free_at = 0
