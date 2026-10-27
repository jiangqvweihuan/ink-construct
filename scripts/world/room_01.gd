extends Node2D

## 残卷山谷 · 一号房间（Demo 主场景）
## 宣纸底 + 两层水墨视差（远山/林影）+ 水墨地面 + 玩家 + 两只小怪 + HUD。
## auto_demo 仅供测试场景勾选：自动走一段、截图、退出。

@export var auto_demo := false

const ROOM_W := 1920.0
const GROUND_Y := 640.0 # 地面碰撞顶面 = 石板带顶缘下 20px，对齐石板的视觉平面
const OUT_DIR := "res://tests/out/"
const WAVE_SPAWNER := preload("res://scripts/systems/wave_spawner.gd")

var _player
var _spawner
var _boss
var _hud
var _ended := false
var _log: FileAccess


func p(msg) -> void:
	print("[R] ", msg)
	if _log:
		_log.store_line("[R] " + str(msg))
		_log.flush()


func _ready() -> void:
	# 不再强制窗口大小：用户在设置里选的分辨率会被这里覆盖打回 1280x720
	BGM.play_bgm("battle") # 进房间切战斗 BGM（破阵）
	# 直接跑场景 = 开新一局；从上一层过来时 Run.active 已为 true，状态（血量/形态/强化）沿用
	if not Run.active:
		Run.start()
	_build_background()
	_build_ground()
	_build_actors()
	_show_blessing() # 每局第一层出发前的赐福三选一（测试/嵌套实例化时不弹）
	if auto_demo:
		_run_demo()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# 已分出胜负（通关/阵亡）或其他面板开着时，Esc 不再弹暂停菜单
	if _ended:
		return
	if get_node_or_null("PauseMenu") != null or get_node_or_null("SwapPanel") != null or get_node_or_null("Blessing") != null:
		return
	var pm = load("res://scenes/ui/pause_menu.tscn").instantiate()
	pm.name = "PauseMenu"
	add_child(pm)


func _load_tex(path: String) -> Texture2D:
	# 走导入管线（.import），导出后同样有效；用 Debug 下资源缺失会打 push_error
	var tex := ResourceLoader.load(path, "Texture2D") as Texture2D
	if tex == null:
		push_error("Room01: 图片加载失败 " + path)
		return null
	p("loaded " + path + " " + str(tex.get_size()))
	return tex


func _build_background() -> void:
	# Boss 房「墨堂深处」：换幽谷背景压暗 + 暗色宫殿剪影，不走普通房那套
	if Run.is_boss_room():
		_build_boss_background()
		return
	# 主背景：横版水墨场景整图（1920x720 已对齐地面线），世界层直接贴
	# 注意：不要在这里加不透明底色以外的覆盖层盖住它
	var bg := Sprite2D.new()
	bg.texture = _load_tex("res://art/environment/background/bg_main.png")
	bg.centered = false
	bg.position = Vector2.ZERO
	add_child(bg)
	_build_decor() # 远处树影与飞鸟，压在角色层后面

	# 前景树冠：框住画面两侧上部，制造林间纵深（z 在角色之前），缩小压淡
	var tree_l := Sprite2D.new()
	tree_l.texture = _load_tex("res://art/environment/foreground/fg_tree_l.png")
	tree_l.centered = false
	tree_l.position = Vector2(-30, -90)
	tree_l.scale = Vector2(0.72, 0.72)
	tree_l.modulate.a = 0.85
	tree_l.z_index = 10
	add_child(tree_l)
	var tree_r := Sprite2D.new()
	tree_r.texture = _load_tex("res://art/environment/foreground/fg_tree_r.png")
	tree_r.centered = false
	tree_r.position = Vector2(ROOM_W - 431.0 * 0.72 + 30.0, -80.0)
	tree_r.scale = Vector2(0.72, 0.72)
	tree_r.modulate.a = 0.85
	tree_r.z_index = 10
	add_child(tree_r)


## 普通房点缀：松柏/樱树/柳树立在远处地面线，天上掠过一队墨鸟
## 全部压在角色层后面（同 z 先加先绘），稍微压灰融入宣纸底
func _build_decor() -> void:
	var defs := [
		{"tex": "res://art/environment/decor/tree_pine.png", "x": 170.0, "scale": 1.15, "sink": 18.0},
		{"tex": "res://art/environment/decor/tree_cherry.png", "x": 660.0, "scale": 1.35, "sink": 10.0},
		{"tex": "res://art/environment/decor/tree_willow.png", "x": 1540.0, "scale": 1.3, "sink": 12.0},
		{"tex": "res://art/environment/decor/tree_pine.png", "x": 1790.0, "scale": 0.95, "sink": 14.0},
	]
	for d in defs:
		var s := Sprite2D.new()
		s.texture = _load_tex(str(d["tex"]))
		var sc := float(d["scale"])
		s.scale = Vector2(sc, sc)
		# 底部落在地面线、稍微下沉吃进石板带，免得像漂着
		s.position = Vector2(float(d["x"]), GROUND_Y + float(d["sink"]) - s.texture.get_height() * sc * 0.5)
		s.modulate = Color(0.72, 0.78, 0.76, 0.92) # 压灰压绿，退到远景
		add_child(s)


## Boss 房「墨堂深处」：幽谷背景放大裁顶压暗，暗色宫殿与断崖剪影立在远处
func _build_boss_background() -> void:
	var bg := Sprite2D.new()
	bg.texture = _load_tex("res://art/environment/background/bg_boss.png")
	bg.centered = false
	bg.scale = Vector2(1.25, 1.25) # 1536x768 -> 1920x960，上缘 240px 裁出画外
	bg.position = Vector2(0, -240)
	bg.modulate = Color(0.45, 0.5, 0.55) # 整体压暗偏冷，幽谷夜色
	add_child(bg)
	var defs := [
		{"tex": "res://art/environment/decor/palace_cliff.png", "x": 340.0, "scale": 1.0, "sink": 26.0},
		{"tex": "res://art/environment/decor/cliff_dark.png", "x": 1250.0, "scale": 1.4, "sink": 20.0},
	]
	for d in defs:
		var s := Sprite2D.new()
		s.texture = _load_tex(str(d["tex"]))
		var sc := float(d["scale"])
		s.scale = Vector2(sc, sc)
		s.position = Vector2(float(d["x"]), GROUND_Y + float(d["sink"]) - s.texture.get_height() * sc * 0.5)
		s.modulate = Color(0.35, 0.38, 0.45, 0.95) # 剪影再压暗，藏进背景
		add_child(s)


func _build_ground() -> void:
	var g := TextureRect.new()
	g.texture = _load_tex("res://art/environment/tilesets/ground_ink.png")
	g.size = Vector2(ROOM_W, 110) # 石板带，顶边羽化
	g.position = Vector2(0, GROUND_Y - 20) # 带顶缘 620，视觉平面在 640=碰撞面
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(g)

	var body := StaticBody2D.new()
	body.position = Vector2(ROOM_W * 0.5, GROUND_Y + 40)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(ROOM_W, 80)
	shape.shape = rect
	body.add_child(shape)
	add_child(body)

	# 左右围墙，把角色关在房间里
	for x in [-20.0, ROOM_W + 20.0]:
		var wall := StaticBody2D.new()
		wall.position = Vector2(x, 360)
		var ws := CollisionShape2D.new()
		var wr := RectangleShape2D.new()
		wr.size = Vector2(40, 720)
		ws.shape = wr
		wall.add_child(ws)
		add_child(wall)


func _build_actors() -> void:
	_player = load("res://scenes/player/player.tscn").instantiate()
	# 脚本编译失败时实例化出来的是裸 CharacterBody2D（没 died/set_upgrades），
	# 宁可在这里报一条清晰错误，也不要等 connect 时刷 Invalid access
	if not _player.has_signal("died"):
		push_error("room_01: 玩家脚本未加载（检查 player.gd 编译错误），本局无法继续")
		return
	# Boss 房玩家进门往场中站：给 Boss 登场留出镜头，也让开场距离够触发它的冲锋
	_player.position = Vector2(460.0 if Run.is_boss_room() else 220.0, 560)
	_player.died.connect(_on_player_died)
	add_child(_player)
	Run.apply_to(_player) # 继承上一层带过来的血量 / 形态 / 强化

	var cam := Camera2D.new()
	cam.position = Vector2(0, -80)
	cam.limit_left = 0
	cam.limit_right = int(ROOM_W)
	cam.limit_top = 0
	cam.limit_bottom = 720
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	_player.add_child(cam)
	cam.make_current()
	Feel.register_camera(cam) # 打击感系统靠这台相机做屏幕震动

	# Boss 房：不刷波次，直接请 Boss 登场；普通房间走波次刷怪
	if Run.is_boss_room():
		_spawn_boss()
	else:
		_spawner = WAVE_SPAWNER.new()
		_spawner.waves = Run.room_config()["waves"]
		_spawner.spawn_y = 560.0
		_spawner.spawn_xs = [820.0, 1120.0, 1440.0, 1720.0]
		_spawner.player_ref = _player
		_spawner.all_cleared.connect(_on_all_cleared)
		add_child(_spawner)

	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	if _boss != null:
		_hud.show_boss(_boss)


## Boss 登场：墨堂深处只有它一个对手，出场先震屏立威
func _spawn_boss() -> void:
	_boss = load("res://scenes/enemies/bosses/boss.tscn").instantiate()
	_boss.type_id = Run.boss_id
	_boss.position = Vector2(1120, 560) # 玩家 460 进门，镜头里能完整看到它登场
	_boss.died.connect(_on_boss_died)
	add_child(_boss)
	_boss.entrance()


# ---------- 通关 / 阵亡结算 ----------

func _on_all_cleared() -> void:
	_ended = true
	# 把玩家现在的血量/形态写进 run，下一层继承
	if is_instance_valid(_player):
		Run.snapshot(_player)
	await get_tree().create_timer(0.8).timeout # 等最后一只倒地动画
	# 三间普通房清空都出强化三选一；第三间的前进方向就是 Boss 房
	_show_upgrade()


## Boss 斩杀 = 通关：倒地动画播完再走结算，尸体多看一会
func _on_boss_died() -> void:
	if _ended:
		return
	_ended = true
	if is_instance_valid(_player):
		Run.snapshot(_player)
	await get_tree().create_timer(1.6).timeout
	Run.active = false # 通关收尾，再来一局开新档
	Meta.add_clear(Run.skull_id) # 局外养成：通关计数 + 当前形态契合 +20
	_show_settlement("通  关", true)


func _on_player_died() -> void:
	if _ended:
		return
	_ended = true
	Run.active = false # 这一局到此为止，再来一局从第一层重开
	await get_tree().create_timer(1.2).timeout # 等阵亡动画
	_show_settlement("阵  亡", false)


func _show_settlement(title_text: String, cleared: bool) -> void:
	if get_node_or_null("Settlement") != null:
		return
	var s = load("res://scenes/ui/settlement_panel.tscn").instantiate()
	s.name = "Settlement"
	s.setup(title_text, cleared)
	add_child(s)


## 每局第一层出发前弹开局赐福三选一；测试场景（auto_demo）或被别的场景嵌套实例化时不弹
func _show_blessing() -> void:
	if auto_demo or get_tree().current_scene != self:
		return
	if Run.room_index != 0 or Run.blessing != "":
		return
	var b = load("res://scenes/ui/blessing_panel.tscn").instantiate()
	b.name = "Blessing"
	# 铁砚护身等改上限的赐福需要重新注入玩家
	b.chosen.connect(func(_id):
		if is_instance_valid(_player):
			Run.apply_to(_player))
	add_child(b)


## 清空房间后的三选一强化：可以花墨骨买一个，也可以直接前进
func _show_upgrade() -> void:
	if get_node_or_null("Upgrade") != null:
		return
	var u = load("res://scenes/ui/upgrade_panel.tscn").instantiate()
	u.name = "Upgrade"
	u.purchased.connect(_on_upgrade_bought)
	u.proceed.connect(_on_proceed)
	add_child(u)


func _on_upgrade_bought() -> void:
	if is_instance_valid(_player):
		Run.apply_to(_player)


func _on_proceed() -> void:
	Run.advance()
	get_tree().paused = false # 强化面板是时停的，进下一层前必须恢复
	get_tree().change_scene_to_file("res://scenes/world/room_01.tscn")


# ---------- 自动演示（测试用） ----------

func _run_demo() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/room_test.log", FileAccess.WRITE)
	# 赐福面板截图 + 任选一个（正常流程是玩家选；demo 里挑墨囊饱满，不影响后续验证）
	var bp = load("res://scenes/ui/blessing_panel.tscn").instantiate()
	bp.name = "Blessing"
	add_child(bp)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("00_blessing")
	bp.pick("bones")
	await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(1.0).timeout
	await _shot("01_view")
	Input.action_press("move_right")
	await get_tree().create_timer(3.0).timeout
	Input.action_release("move_right")
	await _shot("02_walk")
	await get_tree().create_timer(1.5).timeout
	for i in 10:
		_tap("attack")
		await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(0.4).timeout
	# 顺手放三个技能，验证 HUD 冷却遮罩
	_tap("skill")
	await get_tree().create_timer(0.3).timeout
	_tap("skill_sweep")
	await get_tree().create_timer(0.3).timeout
	_tap("skill_ult")
	await get_tree().create_timer(0.8).timeout
	await _shot("03_fight")
	await get_tree().create_timer(1.2).timeout
	await _shot("04_after")
	# 换头验证：补墨骨 -> 化身面板选形态 -> HUD 技能栏应跟着重建
	Score.add_bones(20)
	Meta.debug_unlock_all() # 测试环境直接拉满解锁条件，别让存档挡住换头验证
	await _shot("05_before_swap")
	var panel = load("res://scenes/ui/swap_panel.tscn").instantiate()
	panel.setup(_player) # 必须在 add_child 前：面板 _ready 要读当前形态
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("05b_panel") # 面板开着的样子（时停中）
	panel.select("c023") # 选中即扣墨骨换头并解除时停
	await get_tree().create_timer(0.6).timeout
	await _shot("06_swap")
	_tap("skill")
	await get_tree().create_timer(1.2).timeout
	await _shot("07_swap_skill")
	# 化身谱面板渲染验证（主菜单入口同款面板，这里截图确认排版没破）
	var codex = load("res://scenes/ui/forms_panel.tscn").instantiate()
	add_child(codex)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("08_codex")
	codex.queue_free()
	p("ALL DONE player=" + str(_player.global_position))
	get_tree().quit()


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + "room_" + tag + ".png")
	p("saved " + tag + " err=" + str(err))
