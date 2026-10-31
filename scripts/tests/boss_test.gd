extends Node

## Boss 战冒烟测试：登场 -> 阶段变身 -> 冲锋撞墙 -> 斩杀 -> 通关结算。
## 用 _debug 占位 Boss（c037 骨架放大版）走通全链路，真身转换好后换 ROSTER 即可。

const OUT_DIR := "res://tests/out/"

var _log: FileAccess


func p(msg) -> void:
	print("[B] ", msg)
	if _log:
		_log.store_line("[B] " + str(msg))
		_log.flush()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/boss_test.log", FileAccess.WRITE)

	# 直接进 Boss 房：跳过三关；BOSS_ID 环境变量指定形态（默认 _debug 占位）
	Run.start()
	Run.room_index = Run.ROOMS.size()
	var want := OS.get_environment("BOSS_ID")
	Run.boss_id = want if want != "" else "_debug"
	var room = load("res://scenes/world/room_01.tscn").instantiate()
	add_child(room)
	await get_tree().create_timer(0.5).timeout
	# 玩家拉满血，别在测试途中被 Boss 打死
	room._player.max_hp = 99
	room._player.hp = 99

	var b = room._boss
	p("boss=" + str(b.boss_label) + " hp=" + str(b.hp) + "/" + str(b.max_hp) + " stage=" + str(b.stage))
	await get_tree().create_timer(1.5).timeout # 登场演出
	await _shot("00_entrance")

	# 漏刻·极：Boss 余滞时长减半，自定义冲锋状态也能读取同一倍率。
	b.slow(4.0, 0.45)
	p("boss slow timer=%.1f scale=%.2f（期望 2.0/0.45）" % [b._slow_timer, b._slow_scale])
	if not b._charge.is_empty():
		var old_state: int = b.state
		var old_timer: float = b._state_timer
		b.state = b.S_CHARGING
		b._charge_dir = 1
		b._charge_hit_done = true
		b._custom_tick(0.016)
		p("boss slowed charge vx=%.1f（期望 %.1f）" % [b.velocity.x, float(b._charge.get("speed", 640.0)) * 0.45])
		b.state = old_state
		b._state_timer = old_timer
		b.velocity = Vector2.ZERO
	b._slow_timer = 0.0
	b._slow_scale = 1.0

	# 阶段 1 -> 2：打到 68% 以下；变身期无敌，循环打到 stage 翻篇为止
	var guard := 0
	while b.stage < 1 and guard < 40:
		b.take_damage(2, b.global_position.x - 10.0)
		await get_tree().create_timer(0.3).timeout
		guard += 1
	p("stage2 entered, hp=" + str(b.hp))
	await get_tree().create_timer(4.5).timeout # 变身 3.467s + 僵直 0.6s
	await _shot("01_stage2")

	# 阶段 2 -> 末段（两段形态的 Boss 最高只到 stage1，循环上限按实际段数走）
	var max_stage: int = b._stages.size() - 1
	guard = 0
	while b.stage < max_stage and guard < 40:
		if not is_instance_valid(b) or b.hp <= 0:
			break
		b.take_damage(2, b.global_position.x - 10.0)
		await get_tree().create_timer(0.3).timeout
		guard += 1
	if is_instance_valid(b):
		p("final stage entered, stage=" + str(b.stage) + " hp=" + str(b.hp))
	await get_tree().create_timer(4.5).timeout
	await _shot("02_stage3")

	# 冲锋验证：玩家瞬到场地另一头拉开距离，等 Boss 蓄力/冲锋/撞墙
	room._player.global_position.x = 1520.0
	var saw_charge := false
	guard = 0
	while guard < 60:
		if int(b.state) >= 103: # S_CHARGE_TELE / S_CHARGING
			saw_charge = true
			break
		await get_tree().create_timer(0.2).timeout
		guard += 1
	p("charge seen=" + str(saw_charge))
	await get_tree().create_timer(1.6).timeout
	await _shot("03_charge")

	# 斩杀 -> 通关结算
	guard = 0
	while room.get_node_or_null("Settlement") == null and guard < 100:
		if is_instance_valid(b) and b.hp > 0:
			b.take_damage(3, b.global_position.x - 10.0)
		await get_tree().create_timer(0.3).timeout
		guard += 1
	p("boss dead, settlement visible=" + str(room.get_node_or_null("Settlement") != null))
	await get_tree().create_timer(1.0).timeout
	await _shot("04_clear")

	p("ALL DONE")
	get_tree().quit()


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + "boss_" + str(Run.boss_id) + "_" + tag + ".png")
	p("saved " + tag + " err=" + str(err))
