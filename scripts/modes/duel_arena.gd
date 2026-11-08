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
## 自由视角：平移速度按「屏幕像素/秒」计，缩放不会改变手感（≈10px/帧 @60fps）
const CAMERA_SPEED := 600.0
const CAMERA_ACCEL := 3600.0
const CAMERA_BRAKE := 4800.0
## 触边前的减速缓冲距离（屏幕像素），越靠近边界允许的速度越低
const CAMERA_EDGE_PAD := 110.0
const CAMERA_ZOOM_MIN := 0.55
const CAMERA_ZOOM_MAX := 1.45
const CAMERA_ZOOM_STEP := 1.12
## 地图的纵向像素范围（横向范围见 ARENA_W），用于动态计算视角边界
const MAP_TOP := 0.0
const MAP_H := 720.0
## 召唤安全区：地图正中 40% 的区间。武车的小弟只允许落在这里——
## 远离左右墙、出生点与场地障碍，也不会压进武车 460×200 的大碰撞块里被弹到地下。
const SUMMON_ZONE_MIN := ARENA_W * 0.30
const SUMMON_ZONE_MAX := ARENA_W * 0.70

var _panel
var _camera: Camera2D
var _pan_speed := 0.0 # 当前平移速度（屏幕像素/秒）
var _zoom := 1.0
var _dragging := false
var _red_team: Array = []
var _blue_team: Array = []
var _peers: Array = [] # 全场单位共享的同伴表（即生成时的 all_units），注销实体时原地摘除引用
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
	_update_camera(delta)
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
	_peers = all_units
	for u in all_units:
		u.set("duel_peers", _peers) # 斗蛐蛐不在 enemies 组，软推挤/对穿改看这份同伴表
		u.set("duel_foes", _red_foes if _red_team.has(u) else _blue_foes)
	_sync_foes()
	_assign_targets() # 左右按顺序配对，各打各的，不都往最近那个身上挤
	if _panel != null:
		_panel.bind_fighters(_red_team, _blue_team) # 顶部血条按帧跟着两队走
	_center_camera() # 新一局把视角对回地图中央

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


## 自由视角相机：不写死任何整型边界，边界全部由「地图像素范围 / 当前缩放后的可视尺寸」
## 在运行时算出来。横向 A/D 或拖拽平移，滚轮/双指缩放，两者互不干扰。
func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.position = Vector2(ARENA_W * 0.5, MAP_H * 0.5)
	_camera.zoom = Vector2.ONE
	add_child(_camera)
	_camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null or not _has_fighters():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_by(CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_by(1.0 / CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed # 桌面端也可以按住左键拖动，和手机滑动同一条路径
	elif event is InputEventScreenDrag:
		_drag_pan(event.relative)
	elif event is InputEventMouseMotion and _dragging:
		_drag_pan(event.relative)


## 每帧推进：键盘持续平移 + 平滑加减速 + 触边缓冲。
## 用 _process（渲染帧）而不是定时器轮询，按下到画面移动不超过 1 帧（16.7ms）。
func _update_camera(delta: float) -> void:
	if _camera == null:
		return
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false # 鼠标在 UI 上松开时事件会被吃掉，这里兜底防止拖拽粘住
	var dir := 0.0
	if _has_fighters():
		if Input.is_action_pressed("move_left"):
			dir -= 1.0
		if Input.is_action_pressed("move_right"):
			dir += 1.0
	var target := dir * CAMERA_SPEED
	if dir != 0.0:
		var edge := _pan_bounds().y if dir > 0.0 else _pan_bounds().x
		var dist_px := absf(edge - _camera.position.x) * _zoom
		if dist_px < CAMERA_EDGE_PAD:
			target *= clampf(dist_px / CAMERA_EDGE_PAD, 0.0, 1.0) # 边界缓冲：越近越慢
	var rate := CAMERA_ACCEL if dir != 0.0 else CAMERA_BRAKE
	_pan_speed = move_toward(_pan_speed, target, rate * delta)
	if absf(_pan_speed) < 0.05:
		_pan_speed = 0.0
		return
	_camera.position = _clamp_camera(
		_camera.position + Vector2(_pan_speed * delta / _zoom, 0.0))


## 手指/鼠标拖动：1:1 跟手，向右拖视野向左（地图随手走），键盘与拖动共用同一套边界。
func _drag_pan(rel: Vector2) -> void:
	_pan_speed = 0.0
	_camera.position = _clamp_camera(_camera.position - rel / _zoom)


func _zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	_camera.zoom = Vector2(_zoom, _zoom)
	_camera.position = _clamp_camera(_camera.position)


## 当前缩放下的可移动范围（相机中心坐标）：视口比地图大时直接锁中心。
func _pan_bounds() -> Vector2:
	var view := get_viewport().get_visible_rect().size / _zoom
	var half := view * 0.5
	var x0 := half.x if view.x < ARENA_W else ARENA_W * 0.5
	var x1 := (ARENA_W - half.x) if view.x < ARENA_W else ARENA_W * 0.5
	return Vector2(minf(x0, x1), maxf(x0, x1))


func _clamp_camera(pos: Vector2) -> Vector2:
	var view := get_viewport().get_visible_rect().size / _zoom
	var half := view * 0.5
	var x := ARENA_W * 0.5 if view.x >= ARENA_W else clampf(pos.x, half.x, ARENA_W - half.x)
	var y := (MAP_TOP + MAP_H) * 0.5 if view.y >= MAP_H else clampf(
		pos.y, MAP_TOP + half.y, MAP_TOP + MAP_H - half.y)
	return Vector2(x, y)


func _center_camera() -> void:
	if _camera == null:
		return
	_pan_speed = 0.0
	_camera.position = _clamp_camera(Vector2(ARENA_W * 0.5, MAP_TOP + MAP_H * 0.5))


func _has_fighters() -> bool:
	return not _red_team.is_empty() or not _blue_team.is_empty()


## 一队 N 人：以 base_x 为中心左右排开，统一站在地面线上
func _build_team(ids: Array, stats: Dictionary, base_x: float, step: float, side: int) -> Array:
	var list: Array = []
	var n := ids.size()
	for i in n:
		var e: Dictionary = Roster.find(str(ids[i]))
		# 图鉴里不存在的角色只占位显示，绝不出战：没有可用场景直接跳过。
		if not bool(e.get("available", false)) or str(e.get("scene", "")).is_empty():
			continue
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
			# 小弟的生成安全区：只允许落在正中区间，且必须贴地生成。
			unit.set("summon_min_x", SUMMON_ZONE_MIN)
			unit.set("summon_max_x", SUMMON_ZONE_MAX)
			unit.set("summon_ground_y", GROUND_Y)
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


## 武车撞击边界致死：在碰撞触发的同一帧从实体管理系统注销。
## 血条行保留为 null 占位（面板对 null 只隐藏这一行，行号不会跳动），
## 同伴表 / 敌对表 / 其他单位的锁定目标里的引用全部同步摘掉，再重新配对与结算。
func _forget_unit(unit) -> void:
	for team in [_red_team, _blue_team]:
		for i in team.size():
			if team[i] == unit:
				team[i] = null
	_peers.erase(unit)
	for u in _peers:
		if is_instance_valid(u) and u.get("duel_target") == unit:
			u.set("duel_target", null)
	_red_foes.erase(unit)
	_blue_foes.erase(unit)
	_assign_targets()
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
	_peers = []
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


## 斗蛐蛐场景美术：所有背景层都放在世界坐标里（而不是 CanvasLayer），
## 自由视角缩放/平移时和单位保持同一比例，不会出现「背景不动、地线错位」。
## 层次从远到近：远山 → 雾带 → 宫殿剪影 → 中央光池 → 水墨石板地面 → 地面点缀。
func _build_backdrop() -> void:
	_add_mountain_backdrop()
	_add_palace_silhouettes()
	_add_center_light()
	_add_ground()
	_add_ground_decor()
	_add_screen_overlay()


## 远山：水墨群山做天际线，山脚压在场地地面线以下，只露出山脊与云海。
func _add_mountain_backdrop() -> void:
	var tex := InkTex.load("res://art/environment/background/bg_mountains.jpg")
	if tex == null:
		return
	var sc := ARENA_W * 1.06 / float(tex.get_width())
	var sky := Sprite2D.new()
	sky.texture = tex
	sky.centered = false
	sky.scale = Vector2(sc, sc)
	# 源图 1320px 处是山脚雾带：让它落到地线略下方，山脊自然成为远景
	sky.position = Vector2(-ARENA_W * 0.03, GROUND_Y + 40.0 - 1320.0 * sc)
	sky.modulate = Color(0.50, 0.49, 0.54)
	sky.z_index = -30
	add_child(sky)

	# 山脚往地面过渡的压暗带：让远山沉进地面，而不是像一张贴纸截断
	_add_rect_gradient(
		Vector2(-ARENA_W * 0.06, 250.0), Vector2(ARENA_W * 1.12, GROUND_Y - 250.0),
		[Color(0.03, 0.03, 0.05, 0.0), Color(0.03, 0.03, 0.05, 0.58)], -29)

	# 地平线附近的一条淡雾：分隔远山与战场，增加纵深
	_add_rect_gradient(
		Vector2(-ARENA_W * 0.06, 330.0), Vector2(ARENA_W * 1.12, 210.0),
		[Color(0.62, 0.61, 0.66, 0.0), Color(0.62, 0.61, 0.66, 0.14), Color(0.62, 0.61, 0.66, 0.0)], -28)


## 宫殿剪影：左右各一座，压在地面上、只留暗部轮廓，用来框住中央战场。
func _add_palace_silhouettes() -> void:
	var tex := InkTex.load("res://art/environment/decor/palace_cliff.png")
	if tex == null:
		return
	var defs := [
		{"x": 470.0, "scale": 1.32, "alpha": 0.72},
		{"x": 2730.0, "scale": 1.16, "alpha": 0.64},
	]
	for d in defs:
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		var sc := float(d["scale"])
		s.scale = Vector2(sc, sc)
		s.position = Vector2(float(d["x"]) - tex.get_width() * sc * 0.5, GROUND_Y + 34.0 - tex.get_height() * sc)
		s.modulate = Color(0.17, 0.17, 0.21, float(d["alpha"])) # 压成暗部剪影，避免原画的红/白亮块跳出来
		s.z_index = -26
		add_child(s)


## 中央光池：柔和暖光落在场地中间，把视线引到交战区（不影响任何碰撞与判定）。
func _add_center_light() -> void:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.86, 0.62, 0.11), Color(1.0, 0.86, 0.62, 0.04), Color(1.0, 0.86, 0.62, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var glow := TextureRect.new()
	glow.texture = tex
	glow.position = Vector2(ARENA_W * 0.5 - 1150.0, GROUND_Y - 610.0)
	glow.size = Vector2(2300.0, 620.0)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	glow.z_index = -24
	add_child(glow)


## 地面：水墨石板带 + 下方暗部 + 金色地线，全部以世界坐标 GROUND_Y 对齐脚底。
func _add_ground() -> void:
	var width := ARENA_W * 1.12
	var left := -ARENA_W * 0.06

	var deep := ColorRect.new()
	deep.color = Color(0.025, 0.025, 0.032, 0.98)
	deep.position = Vector2(left, GROUND_Y + 96.0)
	deep.size = Vector2(width, 2200.0)
	deep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deep.z_index = -22
	add_child(deep)

	# 石板下方逐渐没入暗部（不是一刀切的纯黑），远处地面仍然有纵深
	_add_rect_gradient(
		Vector2(left, GROUND_Y + 60.0), Vector2(width, 900.0),
		[Color(0.10, 0.10, 0.12, 0.92), Color(0.03, 0.03, 0.04, 0.98), Color(0.012, 0.012, 0.018, 1.0)], -22)

	var band := TextureRect.new()
	band.texture = InkTex.load("res://art/environment/tilesets/ground_ink.png")
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_TILE
	band.position = Vector2(left, GROUND_Y - 20.0) # 与普通房间同一套对齐：带顶缘在地线上方 20px
	band.size = Vector2(width, 110.0)
	band.modulate = Color(0.74, 0.73, 0.72)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.z_index = -21
	add_child(band)

	# 石板带下缘融进暗部，避免出现一条生硬的色块边界
	_add_rect_gradient(
		Vector2(left, GROUND_Y + 56.0), Vector2(width, 84.0),
		[Color(0.03, 0.03, 0.04, 0.0), Color(0.03, 0.03, 0.04, 0.92)], -20)

	# 地线：一条极细的暖金线，既提示可站立面，也不切割画面
	var line := ColorRect.new()
	line.color = Color(0.86, 0.71, 0.44, 0.30)
	line.position = Vector2(left, GROUND_Y - 1.0)
	line.size = Vector2(width, 1.5)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.z_index = -19
	add_child(line)


## 地面点缀：山石、树、香炉/石碑全部排在中央安全区之外，交战区保持干净。
func _add_ground_decor() -> void:
	var trees := [
		{"tex": "res://art/environment/decor/tree_pine.png", "x": 170.0, "scale": 1.06, "sink": 16.0, "mul": 0.60},
		{"tex": "res://art/environment/decor/tree_cherry.png", "x": 640.0, "scale": 1.22, "sink": 12.0, "mul": 0.40},
		{"tex": "res://art/environment/decor/tree_willow.png", "x": 820.0, "scale": 1.04, "sink": 14.0, "mul": 0.56},
		{"tex": "res://art/environment/decor/tree_pine.png", "x": 2380.0, "scale": 1.10, "sink": 16.0, "mul": 0.60},
		{"tex": "res://art/environment/decor/tree_cherry.png", "x": 2760.0, "scale": 1.24, "sink": 12.0, "mul": 0.40},
		{"tex": "res://art/environment/decor/tree_willow.png", "x": 3070.0, "scale": 1.00, "sink": 14.0, "mul": 0.56},
	]
	for d in trees:
		var tex := InkTex.load(str(d["tex"]))
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		var sc := float(d["scale"])
		s.scale = Vector2(sc, sc)
		s.position = Vector2(float(d["x"]), GROUND_Y + float(d["sink"]) - tex.get_height() * sc * 0.5)
		# 统一压成夜色（樱花压得更狠），原画的粉/绿不会从水墨场景里跳出来
		var mul := float(d["mul"])
		s.modulate = Color(mul, mul * 0.98, mul * 1.06, 0.92)
		s.z_index = -16
		add_child(s)

	var cliffs := [
		{"x": 90.0, "scale": 1.30}, {"x": 880.0, "scale": 0.72},
		{"x": 2400.0, "scale": 0.95}, {"x": 3130.0, "scale": 0.96},
	]
	for d in cliffs:
		var tex := InkTex.load("res://art/environment/decor/cliff_dark.png")
		if tex == null:
			break
		var s := Sprite2D.new()
		s.texture = tex
		var sc := float(d["scale"])
		s.scale = Vector2(sc, sc)
		s.position = Vector2(float(d["x"]), GROUND_Y + 26.0 - tex.get_height() * sc * 0.5)
		s.modulate = Color(0.42, 0.44, 0.50, 0.85)
		s.z_index = -17
		add_child(s)

	var props := [
		{"tex": "res://art/environment/props/decor_censer.png", "x": 400.0, "scale": 0.95},
		{"tex": "res://art/environment/props/decor_stele.png", "x": 2560.0, "scale": 0.92},
	]
	for d in props:
		var tex := InkTex.load(str(d["tex"]))
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		var sc := float(d["scale"])
		s.scale = Vector2(sc, sc)
		s.position = Vector2(float(d["x"]), GROUND_Y - tex.get_height() * sc * 0.5 + 4.0)
		s.modulate = Color(0.62, 0.60, 0.58, 0.90)
		s.z_index = -15
		add_child(s)


## 屏幕层：暗角 + 顶部压暗，只压画面边缘，不遮挡中央战场与操作。
func _add_screen_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1 # 与对战面板同层，先加先绘：暗角在下，面板在上
	add_child(layer)

	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), Color(0.01, 0.01, 0.02, 0.52)])
	g.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var vignette := TextureRect.new()
	vignette.texture = tex
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(vignette)

	# 顶部压暗带：给观战血条 / 返回按钮留出稳定的深色底，避免亮山脊吃掉文字
	var top := TextureRect.new()
	top.texture = _make_v_gradient([Color(0.02, 0.02, 0.03, 0.62), Color(0.02, 0.02, 0.03, 0.0)])
	top.position = Vector2(0, 0)
	top.size = Vector2(1280.0, 132.0)
	top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top.stretch_mode = TextureRect.STRETCH_SCALE
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top)


## 横向铺满、纵向渐变的纯色矩形（世界层用）
func _add_rect_gradient(pos: Vector2, size: Vector2, colors: Array, z: int) -> void:
	var rect := TextureRect.new()
	rect.texture = _make_v_gradient(colors)
	rect.position = pos
	rect.size = size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = z
	add_child(rect)


func _make_v_gradient(colors: Array) -> GradientTexture2D:
	var g := Gradient.new()
	var cols := []
	var offs := []
	for i in colors.size():
		cols.append(colors[i])
		offs.append(float(i) / maxf(1.0, float(colors.size() - 1)))
	g.colors = PackedColorArray(cols)
	g.offsets = PackedFloat32Array(offs)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 4
	tex.height = 128
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	return tex
