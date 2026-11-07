extends Node2D

## 斗蛐蛐场景：山景做底，左右各一只化身，红蓝自动对打，全自动观战。
## 与闯关完全隔离：不读 Run / Meta / Score，不改存档，退出直接回主菜单。

const Fighter = preload("res://scripts/modes/duel_fighter.gd")
const Roster = preload("res://scripts/modes/duel_roster.gd")
const DuelPanel = preload("res://scripts/ui/duel_panel.gd")
const InkTex = preload("res://scripts/ui/ink_tex.gd")
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"

const RED_COLOR := Color(0.82, 0.30, 0.24)
const BLUE_COLOR := Color(0.32, 0.52, 0.88)
const GROUND_Y := 592.0
const RED_X := 396.0
const BLUE_X := 884.0

var _panel
var _red_team: Array = []
var _blue_team: Array = []
var _result_delay := -1.0
var _setup := {}


func _ready() -> void:
	BGM.play_bgm("battle")
	var vw: float = get_viewport().get_visible_rect().size.x
	position.x = maxf(0.0, (vw - 1280.0) * 0.5)
	_build_backdrop()
	_panel = DuelPanel.new()
	add_child(_panel)
	_panel.start_requested.connect(_spawn)
	_panel.rematch_requested.connect(_rematch)
	_panel.config_requested.connect(_clear_fighters)
	_panel.back_requested.connect(_back)


func _process(delta: float) -> void:
	if _result_delay < 0.0:
		return
	_result_delay -= delta
	if _result_delay > 0.0:
		return
	_result_delay = -1.0
	_show_winner()


func _spawn(red_ids: Array, blue_ids: Array, red_stats: Dictionary, blue_stats: Dictionary) -> void:
	_setup = {
		"red_ids": red_ids.duplicate(), "blue_ids": blue_ids.duplicate(),
		"red_stats": red_stats.duplicate(), "blue_stats": blue_stats.duplicate(),
	}
	_clear_fighters()
	_result_delay = -1.0
	_red_team = _build_team(red_ids, red_stats, "红队", RED_COLOR, RED_X, 128.0)
	_blue_team = _build_team(blue_ids, blue_stats, "蓝队", BLUE_COLOR, BLUE_X, -128.0)
	for f in _red_team:
		f.enemies = _blue_team
	for f in _blue_team:
		f.enemies = _red_team
	for f in _red_team:
		f.active = true
	for f in _blue_team:
		f.active = true
	_assign_targets() # 左右按顺序配对，三个人各打各的，别都往最近那个身上挤
	if _panel != null:
		_panel.bind_fighters(_red_team, _blue_team) # 顶部血条按帧跟着两队走


## 两队各自按 x 从小到大排序，第 i 名打对面第 i 名：队列同序推进，路线不交叉，也不会抢同一个目标
func _assign_targets() -> void:
	var red := _red_team.duplicate()
	red.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	var blue := _blue_team.duplicate()
	blue.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	for i in red.size():
		red[i].set_preferred(blue, i)
	for i in blue.size():
		blue[i].set_preferred(red, i)


## 一队 N 人：以 base_x 为中心左右排开，让每个人都站在地面上互不遮挡
func _build_team(ids: Array, stats: Dictionary, tname: String, color: Color, base_x: float, step: float) -> Array:
	var list: Array = []
	var n := ids.size()
	for i in n:
		var f = Fighter.new()
		var off := (float(i) - float(n - 1) * 0.5) * step # 1 人居中，3 人 ±1 格
		f.position = Vector2(base_x + off, GROUND_Y)
		add_child(f)
		f.setup(Roster.find(str(ids[i])), stats, tname, color)
		f.died.connect(_on_died)
		list.append(f)
	return list


func _rematch() -> void:
	if _setup.is_empty():
		return
	_spawn(_setup["red_ids"], _setup["blue_ids"], _setup["red_stats"], _setup["blue_stats"])


func _on_died(_fighter) -> void:
	_check_end()


func _check_end() -> void:
	if _result_delay >= 0.0:
		return
	var red_alive := _alive_count(_red_team)
	var blue_alive := _alive_count(_blue_team)
	if red_alive > 0 and blue_alive > 0:
		return
	_result_delay = 1.0 # 留一点时间看倒地动画


func _alive_count(team: Array) -> int:
	var n := 0
	for f in team:
		if is_instance_valid(f) and not f.is_dead():
			n += 1
	return n


func _show_winner() -> void:
	var red_alive := _alive_count(_red_team)
	var blue_alive := _alive_count(_blue_team)
	var text := "平  局"
	var color := Color(0.88, 0.82, 0.70)
	if red_alive > 0 and blue_alive == 0:
		text = "红 队 胜"
		color = RED_COLOR
	elif blue_alive > 0 and red_alive == 0:
		text = "蓝 队 胜"
		color = BLUE_COLOR
	_panel.show_result(text, color)


func _clear_fighters() -> void:
	for f in _red_team:
		if is_instance_valid(f):
			f.queue_free()
	for f in _blue_team:
		if is_instance_valid(f):
			f.queue_free()
	_red_team = []
	_blue_team = []


func _back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)


func _build_backdrop() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -2
	add_child(layer)

	var bg := TextureRect.new()
	bg.texture = InkTex.load("res://art/environment/background/bg_mountains.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.50, 0.48, 0.52)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.05, 0.58)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)

	# 地面：从 GROUND_Y 往下一整条压暗，两侧多铺一倍宽，覆盖手机加宽的画布
	var ground := ColorRect.new()
	ground.color = Color(0.04, 0.04, 0.04, 0.86)
	ground.position = Vector2(-640, GROUND_Y)
	ground.size = Vector2(2560, 720)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ground)

	var edge := ColorRect.new()
	edge.color = Color(0.82, 0.68, 0.42, 0.35)
	edge.position = Vector2(-640, GROUND_Y - 2)
	edge.size = Vector2(2560, 2)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(edge)
