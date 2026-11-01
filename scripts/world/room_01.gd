extends Node2D

## 残卷山谷 · 一号房间（Demo 主场景）
## 宣纸底 + 两层水墨视差（远山/林影）+ 水墨地面 + 玩家 + 两只小怪 + HUD。
## auto_demo 仅供测试场景勾选：自动走一段、截图、退出。

@export var auto_demo := false

const ROOM_W := 1920.0
const GROUND_Y := 640.0 # 地面碰撞顶面 = 石板带顶缘下 20px，对齐石板的视觉平面
const OUT_DIR := "res://tests/out/"
const WAVE_SPAWNER := preload("res://scripts/systems/wave_spawner.gd")
const DECOR_INTERACTIVE := preload("res://scripts/world/decor_interactive.gd")
const BOSS_DUEL_INTRO := preload("res://scripts/ui/boss_duel_intro.gd")

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


## 普通房点缀：固定 4 棵远景树立在地面线（松/樱/柳），位置与下沉量逐棵调过，别改随机
## 全部压在角色层后面（同 z 先加先绘），只用微量透明融入宣纸底，不做任何调色
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
		s.modulate.a = 0.92 # 只留一点透明融入宣纸底，不调色（原图画质就是最好画质）
		add_child(s)


## Boss 房背景表：每个形态一张主题场景图（1536x768 按 1.25 原比例铺满 1920x960，
## 整图完整不裁、不放大失衡、不加滤镜染色）
## ground = 原图里"画出来的地面线"的 y 坐标（768 高的源图像素系），摆放时让它正好落在
## GROUND_Y——角色脚踩处即画中地面，和小怪房 bg_main 一个逻辑
const BOSS_BG := {
	"_debug": {"tex": "res://art/environment/background/bg_boss.png", "ground": 704.0},
	"c001": {"tex": "res://art/environment/background/bg_boss_c001.png", "ground": 668.0}, # 废墟校场：石板路
	"c008": {"tex": "res://art/environment/background/bg_boss_c008.png", "ground": 675.0}, # 白昼山门：山前沙地
	"c009": {"tex": "res://art/environment/background/bg_boss_c009.png", "ground": 700.0}, # 云海山巅：云坪石滩
	"c015a1": {"tex": "res://art/environment/background/bg_boss_c015a1.png", "ground": 700.0}, # 暮色群峰：湖畔石板路
	"c032": {"tex": "res://art/environment/background/bg_boss_c032.png", "ground": 690.0}, # 阴暗古寺：石板广场
}


## Boss 房「墨堂深处」：按 boss_id 换主题背景，画中地面线对齐 GROUND_Y，单层整图不拼不染
func _build_boss_background() -> void:
	var cfg: Dictionary = BOSS_BG.get(Run.boss_id, BOSS_BG["_debug"])
	var bg := Sprite2D.new()
	bg.texture = _load_tex(str(cfg["tex"]))
	bg.centered = false
	bg.scale = Vector2(1.25, 1.25) # 1536x768 -> 1920x960，原比例铺满
	# 画中地面线对齐 GROUND_Y：角色站在画的地面上，不是站在画前面的舞台上
	bg.position = Vector2(0, GROUND_Y - float(cfg["ground"]) * 1.25)
	add_child(bg)


func _build_ground() -> void:
	# Boss 房场景不分层：背景整图自带地面，不再铺石板带（仅普通房铺）
	if not Run.is_boss_room():
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
		_spawn_decors() # 普通房随机摆 2-3 个互动物件（卷轴/香炉/石碑）
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
	var scene_path := "res://scenes/enemies/bosses/boss.tscn"
	if Run.boss_id == "c009":
		scene_path = "res://scenes/enemies/bosses/mo_ting.tscn"
	elif Run.boss_id == "c015a1":
		scene_path = "res://scenes/enemies/bosses/fen_ding.tscn"
	_boss = load(scene_path).instantiate()
	_boss.type_id = Run.boss_id
	# 无尽缩放必须在 add_child 之前写入（_ready -> _apply_type 会读这两个值）
	_boss.hp_scale = Run.boss_hp_scale()
	_boss.cd_scale = Run.boss_cd_scale()
	_boss.position = Vector2(1120, 560) # 玩家 460 进门，镜头里能完整看到它登场
	_boss.died.connect(_on_boss_died)
	add_child(_boss)
	_boss.entrance()
	if Run.boss_id == "c009" or Run.boss_id == "c015a1":
		var intro := BOSS_DUEL_INTRO.new()
		intro.name = "BossDuelIntro"
		intro.setup(_player, _boss)
		add_child(intro)


## 普通房互动物件：随机 2-3 个卷轴（回血）/ 香炉（重随）/ 石碑（本房 buff），站在地面线上
func _spawn_decors() -> void:
	var kinds := ["scroll", "censer", "stele"]
	kinds.shuffle()
	var count := randi_range(2, 3)
	for i in count:
		var d := DECOR_INTERACTIVE.new()
		d.setup(kinds[i % kinds.size()])
		d.position = Vector2(randf_range(420.0, ROOM_W - 220.0), GROUND_Y)
		add_child(d)
		p("decor 生成: %s @ x=%d" % [kinds[i % kinds.size()], int(d.position.x)])


# ---------- 通关 / 阵亡结算 ----------

func _on_all_cleared() -> void:
	if _ended: # 玩家已阵亡、结算计时已启动时，飞在途中的投射物清场不再叠开强化面板
		return
	_ended = true
	# 把玩家现在的血量/形态写进 run，下一层继承
	if is_instance_valid(_player):
		Run.snapshot(_player)
	await get_tree().create_timer(0.8).timeout # 等最后一只倒地动画
	# 三间普通房清空都出强化三选一；第三间的前进方向就是 Boss 房
	_show_upgrade()


## Boss 斩杀：无归冒险先接第二只不同 Boss；其余冒险通关，无尽打完一层。
func _on_boss_died() -> void:
	if _ended:
		return
	_ended = true
	if is_instance_valid(_player):
		Run.snapshot(_player)
	if not Run.boss_defeated.has(Run.boss_id):
		Run.boss_defeated.append(Run.boss_id)
	await get_tree().create_timer(1.6).timeout
	# 无归二连战：只回 2 血，不回满、不弹强化；第二只仍在当前房间直接登场。
	if Run.mode == Run.MODE_ADVENTURE and Run.difficulty == Run.DIFFICULTIES.size() - 1 and Run.boss_phase == 0:
		Run.boss_phase = 1
		Run.boss_id = str(Run.boss_queue[1])
		Run.hp = mini(Run.max_hp, Run.hp + 2)
		if is_instance_valid(_player):
			Run.apply_to(_player)
		_spawn_boss()
		_hud.show_boss(_boss)
		_ended = false
		return
	if Run.mode == Run.MODE_ENDLESS:
		_show_upgrade() # 这边的「前进」= advance() -> 层数 +1，重开三小关
		return
	Run.active = false # 通关收尾，再来一局开新档
	Meta.add_clear(Run.skull_id) # 局外养成：通关计数 + 当前形态契合 +20
	_show_settlement("通  关", true)


func _on_player_died() -> void:
	if _ended:
		return
	_ended = true
	# 先把玩家当前形态记进 Run：结算面板「再来一局」要沿用同一化身重开
	if is_instance_valid(_player):
		Run.snapshot(_player)
	Run.active = false # 这一局到此为止，再来一局从第一层重开
	await get_tree().create_timer(1.2).timeout # 等阵亡动画
	# 无尽模式：结算标题直接写死在第几层，方便对照自己的最好成绩
	if Run.mode == Run.MODE_ENDLESS:
		_show_settlement("无尽 · 第 %d 层" % Run.depth, false)
		return
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


## 清空房间后的免费三选一强化：选取一项奖励，或直接前进
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
	# 赐福面板截图 + 任选一个（正常流程是玩家选；demo 里挑重随赐福，不影响后续验证）
	var bp = load("res://scenes/ui/blessing_panel.tscn").instantiate()
	bp.name = "Blessing"
	add_child(bp)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("00_blessing")
	bp.pick("reroll")
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
	# 换头验证：化身面板选形态 -> HUD 技能栏应跟着重建
	Meta.debug_unlock_all() # 测试环境直接拉满解锁条件，别让存档挡住换头验证
	await _shot("05_before_swap")
	var panel = load("res://scenes/ui/swap_panel.tscn").instantiate()
	panel.setup(_player) # 必须在 add_child 前：面板 _ready 要读当前形态
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("05b_panel") # 面板开着的样子（时停中）
	panel.select("c023") # 选中即换头并解除时停
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
	# 互动物件验收：demo 走完一趟后还剩几个没触发（被踩过的已 queue_free）
	var alive := 0
	for c in get_children():
		if c is Node2D and c.get_script() == DECOR_INTERACTIVE:
			alive += 1
	p("decor 剩余未触发: %d" % alive)
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
