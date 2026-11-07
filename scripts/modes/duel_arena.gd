extends Node2D

## 斗蛐蛐场景：山景做底，红蓝两队直接实例化正式房间里的敌人，全自动观战。
## 单位复用 scripts/enemies/ 的真实 AI（c016.gd + Boss 脚本），只通过 duel_mode 旁路
## 把「找玩家 / 写存档 / 自动清尸」换成观战语义。
## 与闯关完全隔离：不读 Run / Meta / Score，不改存档，退出直接回主菜单。

const EnemyBase = preload("res://scripts/enemies/c016.gd")
const BossTypes = preload("res://scripts/enemies/boss_types.gd")
const Roster = preload("res://scripts/modes/duel_roster.gd")
const DuelPanel = preload("res://scripts/ui/duel_panel.gd")
const InkTex = preload("res://scripts/ui/ink_tex.gd")
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"

const RED_COLOR := Color(0.82, 0.30, 0.24)
const BLUE_COLOR := Color(0.32, 0.52, 0.88)
const GROUND_Y := 592.0
## 横向等比扩到 3200（原 1280 × 2.5）：武车单体碰撞块宽 460，8 台同场冲撞、转向、
## 召唤时仍有充足余量，不会再挤在一条窄通道里互相堵死。
const ARENA_W := 3200.0
## 出生点随地图等比缩放（原 1280 图上的 396 / 884），左右半场关系保持不变。
const RED_X := ARENA_W * 0.309375
const BLUE_X := ARENA_W * 0.690625
## 普通阵容沿用原间距；带武车时按体型放大，避免多台武车出生就叠成一团。
const TEAM_STEP := 186.0
const CHARIOT_STEP := 460.0
const CHARIOT_CLEARANCE := 470.0
## 相机横向跟随的收敛速度（越大越快贴住战况）
const CAMERA_FOLLOW := 3.5

var _panel
var _camera: Camera2D
var _red_team: Array = []
var _blue_team: Array = []
var _result_delay := -1.0
var _setup := {}
# 两队各自「可攻击目标」共享数组：武车本体永久排除，只收它的召唤物。
# 数组用原地增删维护，所以小弟 spawn 时继承到的引用能一直同步。
var _red_foes: Array = []
var _blue_foes: Array = []
var _foe_sync := 0.0


func _ready() -> void:
	BGM.play_bgm("battle")
	_build_backdrop()
	_build_arena_bodies()
	_build_camera()
	_panel = DuelPanel.new()
	add_child(_panel)
	_panel.start_requested.connect(_spawn)
	_panel.rematch_requested.connect(_rematch)
	_panel.config_requested.connect(_clear_fighters)
	_panel.back_requested.connect(_back)


func _process(delta: float) -> void:
	_follow_camera(delta)
	_foe_sync -= delta
	if _foe_sync <= 0.0:
		_foe_sync = 0.2
		_sync_foes() # 武车随时会召出新小弟，可攻击名单要跟着刷新
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
	EnemyBase.duel_reset() # 上一局残留的出手令牌不能带进新一局
	_result_delay = -1.0
	_red_team = _build_team(red_ids, red_stats, RED_X, _team_step(red_ids), 1)
	_blue_team = _build_team(blue_ids, blue_stats, BLUE_X, -_team_step(blue_ids), 2)
	_disable_friendly_collisions(_red_team)
	_disable_friendly_collisions(_blue_team)
	var all_units := _red_team + _blue_team
	_disable_chariot_collisions(all_units)
	_red_foes = []
	_blue_foes = []
	for u in all_units:
		u.set("duel_peers", all_units) # 斗蛐蛐不在 enemies 组，软推挤/对穿改看这份同伴表
		u.set("duel_foes", _red_foes if _red_team.has(u) else _blue_foes)
	_sync_foes()
	_assign_targets() # 左右按顺序配对，各打各的，不都往最近那个身上挤
	if _panel != null:
		_panel.bind_fighters(_red_team, _blue_team) # 顶部血条按帧跟着两队走
	_follow_camera(1.0) # 新一局直接把镜头对准开战位置，不做缓动


## 一队的出生间距：普通单位沿用原 186；带武车时按武车体型放大，
## 并保证两队各自的排面不越过中场（左右半场关系与原图一致）。
func _team_step(ids: Array) -> float:
	if not ids.has("c001"):
		return TEAM_STEP
	var slots := maxf(1.0, float(ids.size() - 1))
	return clampf((BLUE_X - RED_X - CHARIOT_CLEARANCE) / slots, TEAM_STEP, CHARIOT_STEP)


## 两队各自按 x 从小到大排序，第 i 名打对面第 i 名：队列同序推进，路线不交叉。
## 人数不等时用取模，多打一也能跑；目标死了会在 _find_duel_target 里改追最近的活敌。
## 可攻击名单里没有武车本体，所以任何单位都不会把敌方武车当目标。
func _assign_targets() -> void:
	_sync_foes()
	var red := _alive_team(_red_team)
	var blue := _alive_team(_blue_team)
	if red.is_empty() or blue.is_empty():
		return
	for i in red.size():
		red[i].set("duel_foes", _red_foes)
		red[i].set("duel_target", null if _red_foes.is_empty() else _red_foes[i % _red_foes.size()])
	for i in blue.size():
		blue[i].set("duel_foes", _blue_foes)
		blue[i].set("duel_target", null if _blue_foes.is_empty() else _blue_foes[i % _blue_foes.size()])


## 一队的可攻击名单：武车本体不进名单，只把它的召唤物算作敌方单位。
## 武车没有召唤物时名单为空 —— 对面就只能等，绝不回头去打武车。
func _hittable(team: Array) -> Array:
	var list: Array = []
	for f in team:
		if not is_instance_valid(f) or f.is_queued_for_deletion() or int(f.get("hp")) <= 0:
			continue
		if bool(f.get("duel_untargetable")):
			var subs = f.get("_summons")
			if subs is Array:
				for s in subs:
					if is_instance_valid(s) and not s.is_queued_for_deletion() and int(s.get("hp")) > 0:
						list.append(s)
			continue
		list.append(f)
	list.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	return list


func _sync_foes() -> void:
	_replace_foes(_red_foes, _hittable(_blue_team))
	_replace_foes(_blue_foes, _hittable(_red_team))


func _replace_foes(arr: Array, list: Array) -> void:
	arr.clear()
	arr.append_array(list)


## 同阵营不互撞：两队各自内部一次性关闭碰撞，密集推进时不会互相卡位。
## 必须在开场登记：Boss 脚本（墨霆/芬顶/鸣钟/岁岳/武车）各自重写了 _physics_process，
## 不会走 c016 的逐帧对穿检查，只靠单位自己的逻辑覆盖不到它们。
## 敌对之间保持原有碰撞，命中判定走的始终是距离，不受影响。
func _disable_friendly_collisions(team: Array) -> void:
	for i in team.size():
		for j in range(i + 1, team.size()):
			var a = team[i]
			var b = team[j]
			if not is_instance_valid(a) or not is_instance_valid(b):
				continue
			a.add_collision_exception_with(b)
			b.add_collision_exception_with(a)


## 武车之间互相免疫碰撞：每台武车的实体块是 460×200，靠边刹车/原地转向/等待召唤时
## 体积会完全重叠（车头都被夹在 arena_edge - HEAD_OFFSET 上），互为实体就会把彼此
## 和刚召出来的小弟一起堵死。武车位移是直接写坐标、不靠物理推挤，关掉互撞不影响武撞判定。
func _disable_chariot_collisions(units: Array) -> void:
	for i in units.size():
		var a = units[i]
		if not is_instance_valid(a) or not bool(a.get("duel_untargetable")):
			continue
		for j in range(i + 1, units.size()):
			var b = units[j]
			if not is_instance_valid(b) or not bool(b.get("duel_untargetable")):
				continue
			a.add_collision_exception_with(b)
			b.add_collision_exception_with(a)


## 竞技场比屏幕宽，镜头只做横向跟随：y 固定 360，缩放保持 1，
## 这样 CanvasLayer 里的地线（屏幕 y = GROUND_Y）和世界地面始终对齐，不会出现拉伸或错位。
func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.position = Vector2(ARENA_W * 0.5, 360.0)
	_camera.limit_left = 0
	_camera.limit_right = int(ARENA_W)
	_camera.limit_top = 0
	_camera.limit_bottom = 720
	add_child(_camera)
	_camera.make_current()


## 取场上所有存活单位的横向中点做跟随目标，并夹在场地边界内。
## 战斗集中在半场时镜头不动；武车冲过中场时镜头平滑跟过去，不会漏掉交战。
func _follow_camera(delta: float) -> void:
	if _camera == null:
		return
	var lo := INF
	var hi := -INF
	for u in _red_team + _blue_team:
		if not is_instance_valid(u) or int(u.get("hp")) <= 0:
			continue
		var x := (u as Node2D).global_position.x
		lo = minf(lo, x)
		hi = maxf(hi, x)
	if lo > hi:
		return
	var view_w: float = get_viewport().get_visible_rect().size.x
	var target := (lo + hi) * 0.5
	if view_w < ARENA_W:
		target = clampf(target, view_w * 0.5, ARENA_W - view_w * 0.5)
	else:
		target = ARENA_W * 0.5
	var k := clampf(CAMERA_FOLLOW * delta, 0.0, 1.0)
	_camera.position = Vector2(lerpf(_camera.position.x, target, k), 360.0)


## 一队 N 人：以 base_x 为中心左右排开，统一站在地面线上
func _build_team(ids: Array, stats: Dictionary, base_x: float, step: float, side: int) -> Array:
	var list: Array = []
	var n := ids.size()
	for i in n:
		var e: Dictionary = Roster.find(str(ids[i]))
		var sid := str(e["id"])
		var unit = load(str(e["scene"])).instantiate()
		var script_path := str(BossTypes.SCRIPT_OVERRIDES.get(sid, ""))
		if not script_path.is_empty():
			unit.set_script(load(script_path)) # c008 碎岳 / c032 鸣钟 走专属脚本
		# type_id / duel_mode 必须在 add_child 之前写入：_ready -> _apply_type 会读
		unit.set("type_id", sid)
		unit.set("duel_mode", true)
		unit.set("duel_side", side)
		unit.set("duel_dmg_scale", float(stats["atk"]))
		if sid == "c001":
			# 武车默认 facing=-1：不校正的话红蓝八台会全部往左墙冲、堆在同一个点。
			# 让两队各自朝敌方半场起步，第一次武撞就有意义，也不会挤成一团。
			unit.set("facing", 1 if side == 1 else -1)
		unit.set_meta("duel_name", str(e["name"]))
		unit.position = Vector2(base_x + (float(i) - float(n - 1) * 0.5) * step, GROUND_Y)
		unit.died.connect(_on_died)
		add_child(unit)
		# 血量 / 速度必须在 add_child 之后覆盖：_ready 里会 hp = max_hp
		if sid != "c001": # 武车血量=耐久，保留原机制（撞边掉耐久）
			unit.set("max_hp", maxi(1, int(stats["hp"])))
			unit.set("hp", int(unit.get("max_hp")))
		unit.set("attack_cooldown", float(stats["gap"]))
		unit.set("chase_speed", float(stats["spd"]))
		unit.set("patrol_speed", float(stats["spd"]))
		if sid == "c001":
			unit.set("arena_left", 0.0)
			unit.set("arena_right", ARENA_W)
			unit.call("_apply_facing")
		list.append(unit)
	return list


func _rematch() -> void:
	if _setup.is_empty():
		return
	_spawn(_setup["red_ids"], _setup["blue_ids"], _setup["red_stats"], _setup["blue_stats"])


func _on_died() -> void:
	_assign_targets() # 活着的重新配对 / 改追最近
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
		if is_instance_valid(f) and int(f.get("hp")) > 0 and not f.is_queued_for_deletion():
			n += 1
	return n


func _alive_team(team: Array) -> Array:
	var list: Array = []
	for f in team:
		if is_instance_valid(f) and int(f.get("hp")) > 0 and not f.is_queued_for_deletion():
			list.append(f)
	list.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	return list


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
	EnemyBase.duel_reset()


func _back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)


## 地板与左右墙：敌人都带重力，没有静态地板会直接掉出画面；武车也要靠边撞掉耐久
func _build_arena_bodies() -> void:
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(ARENA_W * 0.5, GROUND_Y + 40.0)
	var floor_shape := CollisionShape2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(ARENA_W + 320.0, 80.0)
	floor_shape.shape = floor_rect
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	for x in [-20.0, ARENA_W + 20.0]:
		var wall := StaticBody2D.new()
		wall.position = Vector2(x, 360.0)
		var wall_shape := CollisionShape2D.new()
		var wall_rect := RectangleShape2D.new()
		wall_rect.size = Vector2(40.0, 720.0)
		wall_shape.shape = wall_rect
		wall.add_child(wall_shape)
		add_child(wall)


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
