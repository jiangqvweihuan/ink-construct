extends Node2D

## 残卷山谷 · 一号房间（Demo 主场景）
## 宣纸底 + 两层水墨视差（远山/林影）+ 水墨地面 + 玩家 + 两只小怪 + HUD。
## auto_demo 仅供测试场景勾选：自动走一段、截图、退出。

@export var auto_demo := false

const ROOM_W := 1920.0
const GROUND_Y := 640.0 # 地面碰撞顶面 = 石板带顶缘下 20px，对齐石板的视觉平面
const OUT_DIR := "res://tests/out/"
const WAVE_SPAWNER := preload("res://scripts/systems/wave_spawner.gd")
const BossTypes := preload("res://scripts/enemies/boss_types.gd")
const DECOR_INTERACTIVE := preload("res://scripts/world/decor_interactive.gd")
const BOSS_DUEL_INTRO := preload("res://scripts/ui/boss_duel_intro.gd")
const MOBILE_GUIDE := preload("res://scripts/ui/mobile_guide.gd")
const NET_SYNC := preload("res://scripts/net/net_sync.gd")

var _player
var _players: Array = [] # 本机双人时含 P1/P2，单人时只有 P1
var _camera: Camera2D
var _spawner
var _boss
var _hud
var _ended := false
var _proceeding := false
var _pending_proceed := false # 联机：房主已点前进但还有队友没选完
var _log: FileAccess


func p(msg) -> void:
	if OS.is_debug_build():
		print("[R] ", msg)
	if _log:
		_log.store_line("[R] " + str(msg))
		_log.flush()


func _ready() -> void:
	# 供玩家/敌人技能位移读取地图宽度，根骨与瞬移类技能据此夹在地图墙内
	set_meta("battle_width", ROOM_W)
	# 不再强制窗口大小：用户在设置里选的分辨率会被这里覆盖打回 1280x720
	BGM.play_bgm("battle") # 进房间切战斗 BGM（破阵）
	BGM.stop_voice() # 联机客机不调 Run.start，这里兜底：进局就停旁白，整局不再触发
	# 直接跑场景 = 开新一局；从上一层过来时 Run.active 已为 true，状态（血量/形态/强化）沿用
	if not Run.active:
		Run.start()
	Achievements.room_begin() # 本房受伤清零，用于无伤房判定
	_build_background()
	_build_ground()
	_connect_lan_choices()
	if Run.net_role == "client":
		# 客户端镜像：敌人/Boss/波次全部由主机权威生成，本地只建背景、两名玩家与 HUD
		_build_actors_client()
		# 主机可能在本场景 _ready 之前就发来了祝福请求，先取出补弹
		var pending := LanNet.take_pending_choice()
		if not pending.is_empty():
			_on_choice_requested(pending)
	else:
		_build_actors()
		_show_blessing() # 每局第一层出发前的赐福三选一（测试/嵌套实例化时不弹）
		if Run.net_role == "host":
			_attach_net_sync()
	if auto_demo:
		_run_demo()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# 客户端是主机世界的镜像，暂停会与主机脱节：联机客机不弹暂停菜单
	if Run.net_role == "client":
		return
	# 已分出胜负（通关/阵亡）或其他面板开着时，Esc 不再弹暂停菜单
	if _ended:
		return
	if get_node_or_null("PauseMenu") != null or get_node_or_null("Blessing") != null:
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
	var base_x := 460.0 if Run.is_boss_room() else 220.0
	_player = _spawn_player(0, Vector2(base_x, 560))
	if _player == null:
		return
	# 联机主机：按实际人数生成 1 主机 + 最多 3 客机的角色；本机双人固定 2 人。
	var total := 1
	if Run.net_role == "host":
		total = maxi(1, Run.player_count())
	elif Run.local_coop:
		total = 2
	for slot in range(1, total):
		_spawn_player(slot, _spawn_offset_pos(base_x, slot))

	_setup_camera(_player)

	# Boss 房：不刷波次，直接请 Boss 登场；普通房间走波次刷怪
	if Run.is_boss_room():
		_spawn_boss()
	else:
		_spawn_decors() # 普通房随机摆 2-3 个互动物件（卷轴/香炉/石碑）
		_spawner = WAVE_SPAWNER.new()
		_spawner.waves = Run.room_config()["waves"]
		_spawner.spawn_y = 560.0
		_spawner.spawn_xs = [760.0, 880.0, 1000.0, 1120.0, 1240.0, 1360.0, 1480.0, 1600.0, 1720.0, 1840.0]
		_spawner.player_ref = _player
		_spawner.player_refs = _players # 4 人局按所有玩家算安全距离
		_spawner.all_cleared.connect(_on_all_cleared)
		add_child(_spawner)

	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	if _boss != null:
		_hud.show_boss(_boss)


## 多人站位：P1 原地，其余按固定偏移错开，避免 4 人叠在同一格。
func _spawn_offset_pos(base_x: float, slot: int) -> Vector2:
	var offsets := [0.0, 130.0, -130.0, 260.0]
	var x := base_x + float(offsets[clampi(slot, 0, offsets.size() - 1)])
	return Vector2(clampf(x, 80.0, ROOM_W - 80.0), 560.0)


## 客户端镜像房间：按主机下发的人数生成受控镜像玩家与 HUD
func _build_actors_client() -> void:
	var spawn_x := 460.0 if Run.is_boss_room() else 220.0
	var total := maxi(1, Run.player_count())
	_player = _spawn_player(0, Vector2(spawn_x, 560))
	if _player == null:
		return
	for slot in range(1, total):
		_spawn_player(slot, _spawn_offset_pos(spawn_x, slot))
	for p in _players:
		if is_instance_valid(p):
			p.net_puppet = true

	# 客机看自己槽位的角色（Run.net_slot），主机看 P1
	var follow = _player
	for p in _players:
		if is_instance_valid(p) and int(p.input_slot) == Run.net_slot:
			follow = p
			break
	_setup_camera(follow)

	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	_attach_net_sync()


func _attach_net_sync() -> void:
	var ns = NET_SYNC.new()
	ns.name = "NetSync"
	ns.room = self
	add_child(ns)


## 生成一名玩家：slot 0 = P1 原键位，slot 1 = 本机双人 P2（方向键 + 小键盘）
func _spawn_player(slot: int, spawn_pos: Vector2):
	var p = load("res://scenes/player/player.tscn").instantiate()
	# 脚本编译失败时实例化出来的是裸 CharacterBody2D（没 died/set_upgrades），
	# 宁可在这里报一条清晰错误，也不要等 connect 时刷 Invalid access
	if not p.has_signal("died"):
		push_error("room_01: 玩家脚本未加载（检查 player.gd 编译错误），本局无法继续")
		return null
	p.input_slot = slot
	p.position = spawn_pos
	p.died.connect(_on_player_died.bind(p))
	add_child(p)
	_players.append(p)
	if Run.is_boss_room() and Run.boss_id == "c008":
		p.set_sui_yue_pressure(true) # 邪佛压场先于状态注入，避免生命与增益被重新写回
	# 联机：复活血量已在 Run.advance() 按 50% 上限写入对应槽位（红蝶封顶 50 仍持续流失，
	# 梅剑进房后由自身「每房回满」补满 60），这里只负责把槽位状态装回角色。
	Run.apply_to(p, slot) # 继承上一层带过来的血量 / 形态 / 强化
	return p


## 还活着的玩家（本机双人时用于判断全灭与镜头接力）
func _alive_players() -> Array:
	var out: Array = []
	for p in _players:
		if is_instance_valid(p) and p.state != p.State.DEAD:
			out.append(p)
	return out


## 结算取状态时优先用幸存者，单人局即 P1
func _survivor():
	var alive := _alive_players()
	if not alive.is_empty():
		return alive[0]
	return _player if is_instance_valid(_player) else null


## 建立主镜头。世界高度固定 720（背景 1920×720），所以镜头不缩放：
## 之前多人把 zoom 拉到 0.86，可视高度变成 837 > 720，limit 夹不住，
## 上下就会露出 clear color（近白），表现为地图发白、显示不完整。
## 本机双人与联机都走这里，避免两边规则不一致。
func _setup_camera(follow) -> void:
	_camera = Camera2D.new()
	_camera.position = Vector2(0, -80)
	_camera.limit_left = 0
	_camera.limit_right = int(ROOM_W)
	_camera.limit_top = 0
	_camera.limit_bottom = 720
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	if follow == null:
		follow = _player
	follow.add_child(_camera)
	_camera.make_current()
	Feel.register_camera(_camera) # 打击感系统靠这台相机做屏幕震动


## 镜头交给指定玩家（P1 阵亡、P2 还在时用）
func _focus_camera(target) -> void:
	if _camera == null or not is_instance_valid(_camera) or not is_instance_valid(target):
		return
	if _camera.get_parent() == target:
		return
	var old := _camera.get_parent()
	if is_instance_valid(old):
		old.remove_child(_camera)
	target.add_child(_camera)
	_camera.position = Vector2(0, -80)
	_camera.make_current()


## 强化 / 赐福对场上每个活着的玩家生效
func _apply_to_all() -> void:
	for p in _alive_players():
		Run.apply_to(p, int(p.input_slot))


func _snapshot_run() -> void:
	# 联机按槽位逐个保存血量；单人局只有 P1，行为与原来一致
	for p in _alive_players():
		Run.snapshot(p, int(p.input_slot))


## Boss 登场：墨堂深处只有它一个对手，出场先震屏立威
func _spawn_boss() -> void:
	var scene_path := str(BossTypes.SCENES.get(Run.boss_id, BossTypes.DEFAULT_SCENE))
	_boss = load(scene_path).instantiate()
	var script_path := str(BossTypes.SCRIPT_OVERRIDES.get(Run.boss_id, ""))
	if not script_path.is_empty():
		_boss.set_script(load(script_path))
	_boss.type_id = Run.boss_id
	# 无尽缩放必须在 add_child 之前写入（_ready -> _apply_type 会读这两个值）
	_boss.hp_scale = Run.boss_hp_scale()
	_boss.cd_scale = Run.boss_cd_scale()
	_boss.position = Vector2(1120, 560) # 玩家 460 进门，镜头里能完整看到它登场
	_boss.died.connect(_on_boss_died)
	add_child(_boss)
	_boss.entrance()
	if BossTypes.ROSTER.has(Run.boss_id):
		var intro := BOSS_DUEL_INTRO.new()
		intro.name = "BossDuelIntro"
		# 在场玩家一起进对峙：本机双人 2 人、联机主机按实际人数最多 4 人
		var duel_players: Array = _alive_players()
		if duel_players.is_empty():
			duel_players = [_player]
		intro.setup_many(duel_players, _boss)
		intro.finished.connect(func(): BGM.play_bgm("boss"))
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
	Achievements.room_cleared() # 记一个房间；本房未受伤则同时记无伤房
	# 把玩家现在的血量/形态写进 run，下一层继承（双人时取幸存者）
	_snapshot_run()
	await get_tree().create_timer(0.8).timeout # 等最后一只倒地动画
	# 这 0.8 秒内仍可能被飞行中的投射物 / 毒素带走，不能让 _ended 吞掉死亡信号
	if _alive_players().is_empty():
		_ended = false
		_on_player_died()
		return
	# 清场等待期内 P1 可能已倒下，镜头需要补交给 P2
	if is_instance_valid(_player) and _player.state == _player.State.DEAD:
		_focus_camera(_survivor())
	# 三间普通房清空都出强化三选一；第三间的前进方向就是 Boss 房
	_show_upgrade()


## Boss 斩杀：无归冒险先接第二只不同 Boss；其余冒险通关，无尽打完一层。
func _on_boss_died() -> void:
	if _ended:
		return
	_ended = true
	Achievements.room_cleared() # 首领房同样算一个房间
	_snapshot_run()
	if not Run.boss_defeated.has(Run.boss_id):
		Run.boss_defeated.append(Run.boss_id)
	await get_tree().create_timer(1.6).timeout
	# 首 Boss 倒地等待期也可能阵亡；不能让 _ended 吞掉死亡信号后直接开第二战。
	if _alive_players().is_empty():
		_ended = false
		_on_player_died()
		return
	# 倒地等待期内 P1 可能已倒下，镜头补交给 P2
	if is_instance_valid(_player) and _player.state == _player.State.DEAD:
		_focus_camera(_survivor())
	# 无归二连战：只回 2 血，不回满、不弹强化；第二只仍在当前房间直接登场。
	if Run.mode == Run.MODE_ADVENTURE and Run.difficulty == Run.DIFFICULTIES.size() - 1 and Run.boss_phase == 0:
		Run.boss_phase = 1
		Run.boss_id = str(Run.boss_queue[1])
		# 多人：压力与回血按所有存活玩家结算，不能只补镜头跟随的那一个
		for p in _alive_players():
			if not is_instance_valid(p):
				continue
			p.set_sui_yue_pressure(Run.boss_id == "c008")
			p._restore_hp(2)
			Run.snapshot(p, int(p.input_slot))
		_apply_to_all()
		_spawn_boss()
		_hud.show_boss(_boss)
		_ended = false
		return
	if Run.mode == Run.MODE_ENDLESS:
		_show_upgrade() # 这边的「前进」= advance() -> 层数 +1，重开三小关
		return
	Run.active = false # 通关收尾，再来一局开新档
	# 局外养成：每位参与者按各自形态记一次通关契合；全局通关数只累计一次
	var participant_skulls := _participant_skulls()
	for i in participant_skulls.size():
		Meta.add_clear(str(participant_skulls[i]), i == 0)
	_show_settlement("通  关", true)


func _on_player_died(dead = null) -> void:
	# 先记最后阵亡槽位：等待期内被飞行物带走的玩家也走这里，结算据此选对应化身
	if is_instance_valid(dead):
		Run.last_death_slot = int(dead.input_slot)
	if _ended:
		return
	if dead == null:
		dead = _player
	# 本机双人 / 联机：只要还有队友站着，就把镜头交给他继续打，不结算
	var alive := _alive_players()
	if not alive.is_empty():
		# 联机阵亡：本房间保持倒地，标记该槽位在下一房间以 50% 上限自动复活
		if Run.net_role != "" and is_instance_valid(dead):
			Run.mark_slot_dead(int(dead.input_slot))
		if dead == _player:
			_focus_camera(alive[0])
		return
	_ended = true
	# 全灭：把所有参与槽位的化身与血量写进 Run，结算面板据此列出完整名单
	for p in _players:
		if is_instance_valid(p):
			Run.snapshot(p, int(p.input_slot))
	Run.active = false # 这一局到此为止，再来一局从第一层重开
	await get_tree().create_timer(1.2).timeout # 等阵亡动画
	# 无尽模式：结算标题直接写死在第几层，方便对照自己的最好成绩
	if Run.mode == Run.MODE_ENDLESS:
		_show_settlement("无尽 · 第 %d 层" % Run.depth, false)
		return
	_show_settlement("阵  亡", false)


## 本局参与玩家的化身（按槽位顺序去重）：多人结算与通关记账都按这份名单
func _participant_skulls() -> Array:
	var out: Array = []
	for p in _players:
		if not is_instance_valid(p):
			continue
		var id := str(p.skull_id)
		if id != "" and not out.has(id):
			out.append(id)
	if out.is_empty():
		out.append(Run.skull_id)
	return out


## 结算名单：每位参与者的槽位、化身、存活状态与血量
func _build_roster() -> Array:
	var out: Array = []
	for p in _players:
		if not is_instance_valid(p):
			continue
		out.append({
			"slot": int(p.input_slot),
			"skull": str(p.skull_id),
			"alive": p.state != p.State.DEAD,
			"hp": int(p.hp),
			"max_hp": int(p.max_hp),
		})
	out.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
	return out


## 兜底：任何玩家被机制冲突带到地板以下时，拉回站立位，避免穿出地图。
func _physics_process(_delta: float) -> void:
	for p in _players:
		if not is_instance_valid(p) or p.global_position.y <= GROUND_Y + 120.0:
			continue
		if p.has_method("clear_ming_zhong_effects"):
			p.call("clear_ming_zhong_effects")
		if p.has_method("mo_ting_release"):
			p.call("mo_ting_release")
		p.global_position = Vector2(clampf(p.global_position.x, 80.0, ROOM_W - 80.0), GROUND_Y - 80.0)
		p.velocity = Vector2.ZERO


func _show_settlement(title_text: String, cleared: bool) -> void:
	if get_node_or_null("Settlement") != null:
		return
	# 客户端不跑结算流程，由主机发 session_end 回大厅
	if Run.net_role == "client":
		return
	if Run.net_role == "host":
		LanNet.host_end_session("对局结束")
		Run.net_role = ""
		Run.local_coop = false
	Achievements.finish_run(cleared) # 单局条件（无伤 / 残血 / 速通 / 空手）在结算前结清
	var s = load("res://scenes/ui/settlement_panel.tscn").instantiate()
	s.name = "Settlement"
	s.setup(title_text, cleared, _build_roster(), Run.last_death_slot)
	add_child(s)


## 每局第一层出发前弹开局赐福三选一；测试场景（auto_demo）或被别的场景嵌套实例化时不弹
func _show_blessing() -> void:
	if auto_demo or get_tree().current_scene != self:
		_show_mobile_guide() # 没有赐福挡着，教程直接上
		return
	if Run.room_index != 0 or Run.blessing_of(0) != "":
		_show_mobile_guide()
		return
	if Run.net_role == "host":
		# 联机：主机统一发牌，两端各自弹自己的面板、各自选（客机收到请求后再弹）
		LanNet.host_begin_choice("blessing")
		return
	var b = load("res://scenes/ui/blessing_panel.tscn").instantiate()
	b.name = "Blessing"
	# 铁砚护身等改上限的赐福需要重新注入玩家
	b.chosen.connect(func(_id):
		_apply_to_all()
		_show_mobile_guide()) # 赐福关掉之后再上讲操作课，两张时停卡不叠在一起
	add_child(b)


# ---------------------------------------------------------------- 联机三选一（祝福 / 强化）

func _connect_lan_choices() -> void:
	if Run.net_role == "":
		return
	if not LanNet.choice_requested.is_connected(_on_choice_requested):
		LanNet.choice_requested.connect(_on_choice_requested)
	if not LanNet.choice_resolved.is_connected(_on_choice_resolved):
		LanNet.choice_resolved.connect(_on_choice_resolved)


## 主机下发了三选一（或客机补取到缓冲请求）：按类型弹出本机面板。
## 联机面板不写 Run、不留重随：选择只上送主机，等 choice_resolved 再统一应用。
func _on_choice_requested(d: Dictionary) -> void:
	var kind := str(d.get("kind", ""))
	var cards = d.get("cards", [])
	if kind == "blessing":
		if get_node_or_null("Blessing") != null:
			return
		var b = load("res://scenes/ui/blessing_panel.tscn").instantiate()
		b.name = "Blessing"
		b.online = true
		b.apply_locally = false
		b.preset_cards = cards if cards is Array else []
		b.chosen.connect(func(id): LanNet.submit_choice(kind, str(id)))
		add_child(b)
	elif kind == "upgrade":
		if get_node_or_null("Upgrade") != null:
			return
		var u = load("res://scenes/ui/upgrade_panel.tscn").instantiate()
		u.name = "Upgrade"
		u.online = true
		u.apply_locally = false
		u.buy_slot = int(Run.net_slot)
		u.show_proceed = Run.net_role == "host"
		u.preset_cards = cards if cards is Array else []
		u.picked.connect(func(key): LanNet.submit_choice(kind, str(key)))
		u.proceed.connect(_on_proceed)
		add_child(u)


## 主机确认所有人选完：应用各自槽位的加成，关掉等待中的面板并恢复暂停。
func _on_choice_resolved(kind: String) -> void:
	get_tree().paused = false
	# 祝福选完就上阵，本端面板可以收掉；强化还要用房主的「继续前进」推进，
	# 房主面板保留到点击前进（换房时随场景销毁），客机只关掉自己的等待面板。
	var keep_upgrade := kind != "blessing" and Run.net_role == "host"
	for n in ["Blessing", "Upgrade"]:
		if n == "Upgrade" and keep_upgrade:
			continue
		var panel := get_node_or_null(n)
		if panel != null:
			panel.queue_free()
	_apply_to_all()
	if kind == "blessing":
		_show_mobile_guide()
	if _pending_proceed:
		_pending_proceed = false
		_on_proceed()


## 触屏版首次进第一场战斗：单独弹一张大字教程卡，讲清拖动 / 点按 / 上划 / 长按
func _show_mobile_guide() -> void:
	if auto_demo or not TouchControls.active or MOBILE_GUIDE.seen:
		return
	if Run.room_index != 0 or Run.is_boss_room():
		return
	MOBILE_GUIDE.seen = true
	await get_tree().create_timer(0.5).timeout # 等入场黑幕散开，别跟转场叠影
	if not is_inside_tree() or get_tree().paused:
		return
	var g := MOBILE_GUIDE.new()
	g.name = "MobileGuide"
	add_child(g)


## 清空房间后的免费三选一强化：选取一项奖励，或直接前进
func _show_upgrade() -> void:
	if Run.net_role == "host":
		# 联机：主机发牌，各端各自选；房主点前进时会等所有人选完再换房
		LanNet.host_begin_choice("upgrade")
		return
	if Run.net_role == "client":
		# 客机没有本地清场事件，正常走 RPC；若请求早于场景就绪则从缓冲补弹
		var d := LanNet.take_pending_choice("upgrade")
		if not d.is_empty():
			_on_choice_requested(d)
		return
	if get_node_or_null("Upgrade") != null:
		return
	var u = load("res://scenes/ui/upgrade_panel.tscn").instantiate()
	u.name = "Upgrade"
	u.purchased.connect(_on_upgrade_bought)
	u.proceed.connect(_on_proceed)
	add_child(u)


func _on_upgrade_bought() -> void:
	_apply_to_all()


func _on_proceed() -> void:
	if _proceeding:
		return
	# 联机房主：还有队友没选完就先挂起，等 choice_resolved 再继续推进
	if Run.net_role == "host" and not LanNet.choices_complete():
		_pending_proceed = true
		return
	_proceeding = true
	Run.advance()
	get_tree().paused = false # 强化面板是时停的，进下一层前必须恢复
	# 联机主机：由 LanNet 统一切场景并先把新 Run 状态发给客机
	if Run.net_role == "host":
		LanNet.host_change_room()
		return
	await LoadVeil.transition_to("res://scenes/world/room_01.tscn", "正在入卷")


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
	# 真实 Esc 输入链：房间 _unhandled_input 打开，暂停层 _input 再次关闭。
	await _demo_escape()
	await get_tree().create_timer(0.15).timeout
	p("Esc 打开暂停=%s 树暂停=%s" % [get_node_or_null("PauseMenu") != null, get_tree().paused])
	await _shot("01_pause")
	await _demo_escape()
	await get_tree().create_timer(0.15).timeout
	p("Esc 继续战斗=%s 树恢复=%s" % [get_node_or_null("PauseMenu") == null, not get_tree().paused])
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
	# 换头验证：直接调用换头入口 -> HUD 技能栏应跟着重建
	Meta.debug_unlock_all() # 测试环境直接拉满解锁条件，别让存档挡住换头验证
	await _shot("05_before_swap")
	_player.swap_skull("c023")
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


func _demo_escape() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	get_viewport().push_input(ev)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = KEY_ESCAPE
	up.keycode = KEY_ESCAPE
	up.pressed = false
	get_viewport().push_input(up)
	await get_tree().process_frame


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + "room_" + tag + ".png")
	p("saved " + tag + " err=" + str(err))
