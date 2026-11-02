extends Node2D

## 试炼场：一块空地 + 任选敌人单挑，专门调技能机制 / 动画 / 判定 bug。
## 双方无限血（生成时血量顶到 999999，打不死，专心看动作与命中）+ 技能零 CD（cooldown_scale 归零）。
## 操作：[ / ] 换玩家形态    , / . 轮换敌人（小怪 + 精英 + Boss 全在表里）    R 重刷当前敌人
##      B 打开局内三选一强化（重随充足，可反复打开补完整条流派）
##      数字键 1~9 模拟受 N 点伤害（测受击分档 / 倒地起身 / 残血待机用）
##      0 键直接把血量压到上限的 15%（测残血待机，比连按掉血快）
## 敌人轮换表直接读 enemy_types / boss_types 两张形态表——以后新增怪/Boss 自动进表，不用改这里。
## 启动 1s 后自动存 tests/out/sandbox_boot.png 供回归验收；命令行加 `-- --shot` 再跑完整自动流程并退出。

const Types := preload("res://scripts/enemies/enemy_types.gd")
const BossTypes := preload("res://scripts/enemies/boss_types.gd")
const Skulls := preload("res://scripts/player/skulls.gd")
const C016Class := preload("res://scripts/enemies/c016.gd")
const WaveSpawner := preload("res://scripts/systems/wave_spawner.gd")
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const OUT_DIR := "res://tests/out/"
const ROOM_W := 1920.0
const GOD_HP := 999999

var _player # PlayerClass
var _enemy: Node2D = null
var _roster: Array = [] # [{id, label, boss}]，轮换表
var _ri := 0
var _skull_ids: Array = []
var _enemy_scenes: Dictionary = {} # 与正式刷怪器共用场景来源，碰撞体和脚本不另配一份
var _info: Label
var _upgrade: CanvasLayer = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_window().size = Vector2i(1280, 720)

	var bg := ColorRect.new()
	bg.color = Color(0.949, 0.918, 0.847)
	bg.size = Vector2(ROOM_W, 720)
	bg.z_index = -10
	add_child(bg)

	# 一块空地：只要一条地面，没任何遮挡
	var ground := StaticBody2D.new()
	ground.position = Vector2(ROOM_W * 0.5, 640)
	add_child(ground)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(ROOM_W, 80)
	var gs := CollisionShape2D.new()
	gs.shape = rect
	ground.add_child(gs)
	var gc := ColorRect.new()
	gc.color = Color(0.102, 0.102, 0.102)
	gc.size = Vector2(ROOM_W, 80)
	gc.position = Vector2(-ROOM_W * 0.5, -40)
	ground.add_child(gc)

	# 左右空气墙：与正式房间一致，防止角色或冲刺中的敌人离开试炼场。
	for x in [-20.0, ROOM_W + 20.0]:
		var wall := StaticBody2D.new()
		wall.position = Vector2(x, 360)
		add_child(wall)
		var wall_shape := CollisionShape2D.new()
		var wall_rect := RectangleShape2D.new()
		wall_rect.size = Vector2(40, 720)
		wall_shape.shape = wall_rect
		wall.add_child(wall_shape)

	# 正式房小怪/精英的场景清单就是唯一来源：各自碰撞体、脚本与后续修改同步带进来。
	for scene_path in WaveSpawner.NORMAL_SCENES + WaveSpawner.ELITE_SCENES:
		var probe = load(scene_path).instantiate()
		_enemy_scenes[str(probe.type_id)] = scene_path
		probe.free()

	_player = load(PLAYER_SCENE).instantiate()
	_player.position = Vector2(380, 560)
	add_child(_player)
	Run.apply_to(_player) # 与正式房使用同一形态、强化和局外养成注入，再覆盖试炼场专用规则
	_player.max_hp = GOD_HP
	_player.hp = GOD_HP
	_player.cooldown_scale = 0.0 # 技能零冷却：专心试招不用等 CD（冷却 = 表配 × 本倍率 × 契合）
	_player.dash_cooldown = 0.0 # 冲刺也不卡手
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
	Feel.register_camera(cam)
	_skull_ids = Skulls.ids()

	# 轮换表 = 小怪/精英形态表 + Boss 形态表（过滤 _debug 占位与 DEFAULT_ID 重复项）
	for id in Types.TYPES.keys():
		_roster.append({"id": id, "label": str(Types.TYPES[id].get("label", id)), "boss": false})
	for id in BossTypes.BOSSES.keys():
		if str(id) == "_debug" or str(id) == str(BossTypes.DEFAULT_ID):
			continue
		_roster.append({"id": id, "label": str(BossTypes.BOSSES[id].get("label", id)) + "【Boss】", "boss": true})

	_info = Label.new()
	_info.position = Vector2(24, 18)
	_info.add_theme_font_size_override("font_size", 20)
	var info_layer := CanvasLayer.new()
	add_child(info_layer)
	info_layer.add_child(_info)

	_spawn_enemy()
	_update_info()

	# 启动自验：渲染稳定后存一张 boot 图（回归只看这张图 + 日志，不用人工开场景）
	await get_tree().create_timer(1.0).timeout
	await _shot("sandbox_boot")
	if "--shot" in OS.get_cmdline_user_args():
		await _auto_tour()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_BRACKETLEFT:
			_cycle_skull(-1)
		KEY_BRACKETRIGHT:
			_cycle_skull(1)
		KEY_COMMA:
			_cycle_enemy(-1)
		KEY_PERIOD:
			_cycle_enemy(1)
		KEY_R:
			_spawn_enemy() # 重刷当前敌人（换动画/重置位置用）
			_update_info()
		KEY_B:
			_open_upgrade()
		KEY_0:
			# 一键残血：直接压到上限的 15%，待机下一帧就会自动切残血动画（形态表 low_hp_ratio=0.2）
			_player.hp = maxi(1, int(round(_player.max_hp * 0.15)))
			_player.hp_changed.emit(_player.hp, _player.max_hp)
			_update_info()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			# 数字键 = 模拟受到 N 点伤害，走玩家真实受击入口，能完整验证分档/倒地/待机切换。
			# 先清掉受伤后 0.8s 的短无敌，否则连按几下只有第一下生效，测起来很别扭（仅试炼场这么干）
			_player._hurt_invincible = 0.0
			_player.hurt(e.keycode - KEY_0)
			_update_info()


func _open_upgrade() -> void:
	if is_instance_valid(_upgrade):
		return
	Run.active = true
	Run.skull_id = _player.skull_id
	Run.hp = GOD_HP
	Run.max_hp = GOD_HP
	Run.supply_upgrade_rerolls = maxi(Run.supply_upgrade_rerolls, 99)
	_upgrade = load("res://scenes/ui/upgrade_panel.tscn").instantiate()
	_upgrade.title_text = "试炼场 · 免费强化"
	_upgrade.proceed_text = "返回试炼场"
	_upgrade.purchased.connect(_on_upgrade_bought)
	_upgrade.proceed.connect(_close_upgrade)
	add_child(_upgrade)


func _on_upgrade_bought() -> void:
	Run.apply_to(_player)
	# 强化正常结算后恢复试炼场规则，避免通用生命/冷却卡破坏无限血与零 CD。
	_player.max_hp = GOD_HP
	_player.hp = GOD_HP
	_player.cooldown_scale = 0.0
	_player.dash_cooldown = 0.0
	_player.hp_changed.emit(_player.hp, _player.max_hp)
	_update_info()


func _close_upgrade() -> void:
	if is_instance_valid(_upgrade):
		_upgrade.queue_free()
	_upgrade = null
	get_tree().paused = false
	_update_info()


func _cycle_skull(dir: int) -> void:
	var i := _skull_ids.find(_player.skull_id)
	_player.swap_skull(_skull_ids[wrapi(i + dir, 0, _skull_ids.size())])
	_player.max_hp = GOD_HP # 换头后血量再顶满（swap 不动 max_hp，保险一手）
	_player.hp = GOD_HP
	_update_info()


func _cycle_enemy(dir: int) -> void:
	_ri = wrapi(_ri + dir, 0, _roster.size())
	_spawn_enemy()
	_update_info()


func _spawn_enemy() -> void:
	_player.clear_ming_zhong_effects()
	if _enemy != null and is_instance_valid(_enemy):
		# 旧怪若占着全局出手令牌，free 前先还回来，否则新怪永远出不了手
		if C016Class._attacker == _enemy:
			C016Class._attacker = null
		_enemy.queue_free()
	var info: Dictionary = _roster[_ri]
	var scene_path := str(BossTypes.SCENES.get(info["id"], BossTypes.DEFAULT_SCENE)) if info["boss"] else str(_enemy_scenes.get(info["id"], ""))
	if scene_path.is_empty():
		push_error("试炼场缺少正式房敌人场景映射: %s" % info["id"])
		return
	_enemy = load(scene_path).instantiate()
	var script_path := str(BossTypes.SCRIPT_OVERRIDES.get(info["id"], ""))
	if not script_path.is_empty():
		_enemy.set_script(load(script_path))
	_enemy.type_id = info["id"] # add_child 才跑 _ready/_apply_type，先设形态
	if info["id"] == "c001":
		_enemy.arena_right = ROOM_W
	_enemy.position = Vector2(900, 560)
	add_child(_enemy)
	var player_hp := int(_player.hp)
	_player.clear_sui_yue_effects()
	_player.set_sui_yue_pressure(info["id"] == "c008")
	_player.max_hp = GOD_HP
	_player.hp = mini(player_hp, GOD_HP)
	_player.cooldown_scale = 0.0
	_player.dash_cooldown = 0.0
	_player.hp_changed.emit(_player.hp, _player.max_hp)
	if info["id"] != "c001": # 武车保留耐久，才能试完整个波次与阵亡流程
		_enemy.max_hp = GOD_HP
		_enemy.hp = GOD_HP


func _audit_formal_sync() -> bool:
	var all_ok := true
	var player_ok: bool = _player.scene_file_path == PLAYER_SCENE
	print("[SB] sync player scene=", _player.scene_file_path, " ok=", player_ok)
	all_ok = all_ok and player_ok
	for info in _roster:
		var id := str(info["id"])
		var scene_path := str(BossTypes.SCENES.get(id, BossTypes.DEFAULT_SCENE)) if info["boss"] else str(_enemy_scenes.get(id, ""))
		var script_path := str(BossTypes.SCRIPT_OVERRIDES.get(id, "")) if info["boss"] else ""
		var source_ok: bool = not scene_path.is_empty() and ResourceLoader.exists(scene_path)
		if not script_path.is_empty():
			source_ok = source_ok and ResourceLoader.exists(script_path)
		print("[SB] sync ", id, " scene=", scene_path, " script=", script_path if not script_path.is_empty() else "<scene>", " ok=", source_ok)
		all_ok = all_ok and source_ok
	print("[SB] formal scene sync=", all_ok)
	return all_ok


func _update_info() -> void:
	var skull: Dictionary = Skulls.get_profile(_player.skull_id)
	var info: Dictionary = _roster[_ri]
	_info.text = "形态 %d/%d  %s（%s）    敌人 %d/%d  %s（%s）    血量 %d/%d\n[ ] 换形态    , . 换敌人    B 三选一强化（已选 %d）    R 重刷敌人    1~9 模拟受 N 点伤    0 压到残血    无限血 + 零CD" % [
		_skull_ids.find(_player.skull_id) + 1, _skull_ids.size(),
		str(skull["label"]), _player.skull_id,
		_ri + 1, _roster.size(), str(info["label"]), str(info["id"]),
		_player.hp, _player.max_hp, Run.upgrades.size()]


## 回归自动流程：换一只形态、刷一只精英、刷一只 Boss，各截一张图后退出
func _auto_tour() -> void:
	if not _audit_formal_sync():
		get_tree().quit(1)
		return
	# 首只敌人按逗号会绕到最后一只 Boss，覆盖用户实际切换路径，避免只测首只 Boss。
	print("[SB] cycle left from first")
	_cycle_enemy(-1)
	await get_tree().create_timer(0.5).timeout
	await _shot("sandbox_cycle_left")
	print("[SB] cycle left ok enemy=", _roster[_ri]["id"])
	_open_upgrade()
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("sandbox_upgrade")
	if is_instance_valid(_upgrade) and not _upgrade._cards.is_empty():
		var key := str(_upgrade._cards[0])
		_upgrade._on_card(key)
		await get_tree().process_frame
		print("[SB] upgrade bought=", key, " level=", Run.level(key), " hp=", _player.hp, " cd_scale=", _player.cooldown_scale)
		_close_upgrade()
		await get_tree().create_timer(0.2).timeout
	_cycle_skull(1)
	await get_tree().create_timer(0.5).timeout
	# 找第一只精英与第一只 Boss 各刷一次（不依赖具体 id，表变了也能跑）
	var elite_i := -1
	var boss_i := -1
	for i in _roster.size():
		if not _roster[i]["boss"] and elite_i < 0 and bool(Types.TYPES[_roster[i]["id"]].get("elite", false)):
			elite_i = i
		elif _roster[i]["boss"] and boss_i < 0:
			boss_i = i
	if elite_i >= 0:
		_ri = elite_i
		_spawn_enemy()
		await get_tree().create_timer(0.5).timeout
		await _shot("sandbox_elite")
	if boss_i >= 0:
		_ri = boss_i
		_spawn_enemy()
		await get_tree().create_timer(0.8).timeout
		await _shot("sandbox_boss")
	await _pipa_visual_tour()
	for i in _roster.size():
		if _roster[i]["id"] == "c008":
			_ri = i
			_spawn_enemy()
			await get_tree().create_timer(0.5).timeout
			var script_ok: bool = _enemy.get_script() == load("res://scripts/enemies/sui_yue.gd")
			var scene_ok: bool = _enemy.scene_file_path == BossTypes.DEFAULT_SCENE
			var pressure_ok: bool = _player._sui_yue_pressure
			print("[SB] c008 scene_ok=", scene_ok, " script_ok=", script_ok, " pressure_ok=", pressure_ok)
			await _shot("sandbox_sui_yue")
			get_tree().quit(0 if scene_ok and script_ok and pressure_ok else 1)
			return
	get_tree().quit()


## 绛弦正式玩家实机验收：真实状态机驱动动作，截图供检查位移、连段与受击衔接。
func _pipa_visual_tour() -> void:
	for i in _roster.size():
		if _roster[i]["id"] == "c016":
			_ri = i
			break
	_spawn_enemy()
	_enemy.set_physics_process(false)
	_enemy.set_process(false)
	_player.swap_skull("z002")
	_player.skill_config = (_player.skill_config as Dictionary).duplicate(true)
	_player.position = Vector2(430, 560)
	_enemy.position = Vector2(700, 560)
	_player._attack_recovery = 0.0
	_update_info()
	await get_tree().create_timer(1.5).timeout # 等换形光柱播完，避免遮住待机与首段普攻
	await _shot("sandbox_pipa_idle")
	for i in _player.attacks.size():
		_player._attack_recovery = 0.0
		_player._start_attack(i)
		var hit: Dictionary = _player.attacks[i]["hits"][0]
		await get_tree().create_timer(float(hit["at"])).timeout
		await _shot("sandbox_pipa_atk%d" % (i + 1))
		await get_tree().create_timer(maxf(0.05, float(_player.attacks[i]["lock"]) - float(hit["at"]) + 0.05)).timeout
	for anim in ["run-", "skill13_02-cankao"]:
		_player.position = Vector2(430, 560)
		_player.skill_config["run-"]["pool"] = [anim]
		_player._skill_cds["run-"] = 0.0
		_player._start_skill("run-")
		await get_tree().create_timer(0.30).timeout
		await _shot("sandbox_pipa_k_" + anim)
		await get_tree().create_timer(0.8).timeout
		print("[SB] pipa K ", anim, " end_x=", _player.global_position.x, " state=", _player.state)
	_player.position = Vector2(500, 560)
	Input.action_press("jump")
	await get_tree().create_timer(0.12).timeout
	Input.action_release("jump")
	await get_tree().create_timer(0.10).timeout
	await _shot("sandbox_pipa_jump_up")
	await get_tree().create_timer(0.32).timeout
	await _shot("sandbox_pipa_jump_down")
	await get_tree().create_timer(0.55).timeout
	_player._hurt_invincible = 0.0
	_player.hurt(4)
	await get_tree().create_timer(0.55).timeout
	await _shot("sandbox_pipa_knockdown")
	await get_tree().create_timer(3.0).timeout
	await _shot("sandbox_pipa_getup")
	print("[SB] pipa visual tour done state=", _player.state, " anim=", _player._current_anim)


func _shot(tag: String) -> void:
	await get_tree().process_frame
	RenderingServer.force_draw()
	var err := get_viewport().get_texture().get_image().save_png(OUT_DIR + tag + ".png")
	print("[SB] saved ", tag, " err=", err)
