extends Node

const BossTypes := preload("res://scripts/enemies/boss_types.gd")

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
	var intro = room.get_node_or_null("BossDuelIntro")
	if BossTypes.is_codex_boss(Run.boss_id):
		p("duel intro created=" + str(intro != null) + " anim=" + str(BossTypes.get_boss(Run.boss_id).get("intro", {})))
		if intro == null:
			get_tree().quit(1)
			return
		assert(intro._duel_fx != null, "Boss 对峙必须创建 E21022 节点")
		assert(intro._duel_fx.sprite != null, "Boss 对峙特效必须包含真实 SpineSprite")
		assert(intro._duel_fx.sprite.get("skeleton_data_res") != null, "Boss 对峙 Spine 骨架必须已挂载")
		var duel_state = intro._duel_fx.sprite.call("get_animation_state")
		var duel_track = duel_state.call("get_current", 0)
		assert(duel_track != null and str(duel_track.call("get_animation").call("get_name")) == "action", "Boss 对峙必须使用实测 action 动画")
		var has_vs := false
		for label in intro.find_children("*", "Label", true, false):
			if str(label.text) == "VS":
				has_vs = true
		assert(not has_vs, "Boss 对峙只显示斗法特效，不再叠加 VS")
		await get_tree().create_timer(0.85).timeout
		await _shot("00_duel_intro")
		if is_instance_valid(intro):
			await intro.finished
	# 玩家拉满血，别在测试途中被 Boss 打死
	room._player.max_hp = 99
	room._player.hp = 99

	var b = room._boss
	p("boss=" + str(b.boss_label) + " hp=" + str(b.hp) + "/" + str(b.max_hp) + " stage=" + str(b.stage))
	await get_tree().create_timer(1.5).timeout # 登场演出
	await _shot("00_entrance")

	# Boss 词条默认规则：非普攻出手期间免疫规则级击飞/击退/晕眩（时停仍可打断，由各 Boss 专项测试覆盖）。
	if b._attack_anims.size() >= 2:
		var saved_state: int = b.state
		var saved_move: String = b._attack_move
		var saved_velocity: Vector2 = b.velocity
		var saved_invincible: bool = b._invincible
		b._invincible = false
		b.state = b.State.ATTACK
		b._attack_move = str(b._attack_anims[1])
		b.launch(1, 900.0, 400.0, true)
		b.knock_back(1, 900.0, 2, true)
		b.stun(2.0, true)
		var protected: bool = b.state == b.State.ATTACK and b.velocity == saved_velocity and is_zero_approx(b._stun_timer)
		p("non-basic move protected=" + str(protected))
		if not protected:
			p("FAIL 非普攻出手仍被规则级控制打断")
			get_tree().quit(1)
			return
		b._attack_move = str(b._attack_anims[0])
		b.launch(1, 900.0, 400.0, true)
		var basic_lifted: bool = b.state == b.State.ATTACK and b.velocity.y == -200.0
		p("basic move liftable=" + str(basic_lifted))
		if not basic_lifted:
			p("FAIL 普攻出手应仍可被规则级击飞挑起")
			get_tree().quit(1)
			return
		b.state = saved_state
		b._attack_move = saved_move
		b.velocity = saved_velocity
		b._invincible = saved_invincible
		b._stun_timer = 0.0
		b._root_timer = 0.0

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
		var expected_vx: float = float(b._charge.get("speed", 640.0)) * 0.45
		p("boss slowed charge vx=%.1f（期望 %.1f）" % [b.velocity.x, expected_vx])
		if not is_equal_approx(b.velocity.x, expected_vx):
			p("FAIL 自定义冲锋未应用余滞倍率")
			get_tree().quit(1)
			return
		b.state = old_state
		b._state_timer = old_timer
		b.velocity = Vector2.ZERO

	# 基类自定义状态必须自行推进 DoT 与余滞；独立 Boss 由各自专项测试覆盖。
	if b.get_script() == load("res://scripts/enemies/boss.gd"):
		var old_state: int = b.state
		var old_timer: float = b._state_timer
		var hp_before: int = b.hp
		var slow_before: float = b._slow_timer
		b.apply_bleed(2)
		b.apply_poison(2.0)
		b.state = b.S_CHARGE_TELE
		b._state_timer = 10.0
		b._physics_process(1.0)
		var status_ok: bool = b.hp == hp_before - 4 and is_equal_approx(b._slow_timer, maxf(0.0, slow_before - 1.0))
		p("custom status DoT hp=%d/%d slow=%.2f（期望 %d/%.2f）" % [b.hp, hp_before, b._slow_timer, hp_before - 4, maxf(0.0, slow_before - 1.0)])
		if not status_ok:
			p("FAIL 基类自定义状态未持续推进 DoT 或余滞")
			get_tree().quit(1)
			return
		b.hp = hp_before
		b._bleed_stacks = 0
		b._bleed_time = 0.0
		b._bleed_acc = 0.0
		b._poison_time = 0.0
		b._poison_acc = 0.0
		b.state = old_state
		b._state_timer = old_timer
		b.velocity = Vector2.ZERO
	b._slow_timer = 0.0
	b._slow_scale = 1.0

	# 多阶段 Boss 依次打到后续阶段；鸣钟等单阶段 Boss 不为此空耗伤害。
	var max_stage: int = b._stages.size() - 1
	var guard := 0
	if max_stage > 0:
		while is_instance_valid(b) and b.hp > 0 and b.stage < mini(1, max_stage) and guard < 40:
			b.take_damage(2, b.global_position.x - 10.0)
			await get_tree().create_timer(0.3).timeout
			guard += 1
		if not is_instance_valid(b) or b.hp <= 0:
			p("FAIL boss died before stage transition")
			get_tree().quit(1)
			return
		p("stage2 entered, hp=" + str(b.hp))
		await get_tree().create_timer(4.5).timeout # 变身 3.467s + 僵直 0.6s
		await _shot("01_stage2")

		guard = 0
		while is_instance_valid(b) and b.hp > 0 and b.stage < max_stage and guard < 40:
			b.take_damage(2, b.global_position.x - 10.0)
			await get_tree().create_timer(0.3).timeout
			guard += 1
		if not is_instance_valid(b) or b.hp <= 0:
			p("FAIL boss died before final stage")
			get_tree().quit(1)
			return
		p("final stage entered, stage=" + str(b.stage) + " hp=" + str(b.hp))
		await get_tree().create_timer(4.5).timeout
		await _shot("02_stage3")
	else:
		p("single-stage boss, transform smoke skipped")

	# 通用冲锋只对配置了 _charge 的 Boss 生效；鸣钟的旋征由专项测试覆盖。
	if not b._charge.is_empty():
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
	else:
		p("charge not configured, charge smoke skipped")

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
	# 无头下 frame_post_draw 不发射：改用 process_frame + force_draw，并以空图判断兜底。
	await get_tree().process_frame
	# 无头下没有可读帧，直接跳过截图，避免 dummy 纹理报错。
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw()
	var img = get_viewport().get_texture().get_image()
	if img == null:
		p("screenshot unavailable " + tag)
		return
	var err = img.save_png(OUT_DIR + "boss_" + str(Run.boss_id) + "_" + tag + ".png")
	p("saved " + tag + " err=" + str(err))
