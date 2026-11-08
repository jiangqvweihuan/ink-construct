extends Node

## 结算冒烟测试：test_clear=true 杀光小怪看通关面板，否则打死玩家看阵亡面板

@export var test_clear := false

const OUT_DIR := "res://tests/out/"

var _log: FileAccess
var _ink_before := 0
var _checks := 0
var _failed := 0

func p(msg) -> void:
	print("[S] ", msg)
	if _log:
		_log.store_line("[S] " + str(msg))
		_log.flush()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/settlement_test.log", FileAccess.WRITE)
	Meta.persist = false # 结算会真实增加墨锭，测试进程内验证即可，不写玩家存档

	var room = load("res://scenes/world/room_01.tscn").instantiate()
	if test_clear:
		# 无归通关：连续斩杀两只不同 Boss，验证中间不弹强化、结算留下双印。
		Run.start(Run.MODE_ADVENTURE, "c021", Run.DIFFICULTIES.size() - 1)
		Run.room_index = Run.ROOMS.size()
		Run.boss_queue = ["_debug", "c008"]
		Run.boss_id = "_debug"
	else:
		Run.start(Run.MODE_ADVENTURE, "c021", 3)
	add_child(room)
	await get_tree().create_timer(1.0).timeout
	if test_clear:
		room.reparent(get_tree().root)
		get_tree().current_scene = room
		await get_tree().process_frame
		ScreenFX._process(0.0)
		p("鼠标战斗显隐：scene=%s battle=%s mode=%d" % [get_tree().current_scene.scene_file_path, ScreenFX._in_active_battle(), Input.mouse_mode])
		_check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "战斗房间内隐藏自定义鼠标")
	_ink_before = Meta.ink

	if test_clear:
		# 玩家拉满血防止被 Boss 反杀；变身期无敌，分阶段持续打到死
		room._player.max_hp = 99
		room._player.hp = 99
		var waited := 0.0
		var saw_first := false
		var saw_second := false
		var first_pressure := true
		var second_pressure := false
		while room.get_node_or_null("Settlement") == null and waited < 120.0:
			room._player.max_hp = 99
			room._player.hp = 99
			room._player._invincible = true
			var b = room._boss
			if is_instance_valid(b) and b.hp > 0:
				b.take_damage(8, b.global_position.x - 10.0)
			if is_instance_valid(b) and str(b.type_id) == "_debug" and not saw_first:
				saw_first = true
				first_pressure = bool(room._player.get("_sui_yue_pressure"))
			if is_instance_valid(b) and str(b.type_id) == "c008" and not saw_second:
				saw_second = true
				second_pressure = bool(room._player.get("_sui_yue_pressure"))
				p("第二只 Boss 已登场：phase=%d，强化面板=%s，碎岳压场=%s（期望 1 / false / true）" % [Run.boss_phase, room.get_node_or_null("Upgrade") != null, second_pressure])
			await get_tree().create_timer(0.4).timeout
			waited += 0.4
		p("cleared, waited=%.1f second=%s defeated=%s 首战压场=%s 二战压场=%s（期望首战无压场/二战压场）" % [waited, saw_second, str(Run.boss_defeated), first_pressure, second_pressure])
		_check(not first_pressure and second_pressure, "无归连战第二只碎岳启用压场，第一只非碎岳不压场")
		await get_tree().create_timer(1.0).timeout
		await _shot("clear")
		var clear_panel = room.get_node_or_null("Settlement")
		_check_result_fx(clear_panel, "win")
		_check_ink(true)
	else:
		# 先让敌人触发红蝶留下历史受击，再完全因流失死亡：结算不得重演这名敌人。
		var red_attacker = room._spawner._alive[0] if not room._spawner._alive.is_empty() else null
		room._player.hurt(20, Vector2.ZERO, red_attacker, {"anim": "skill01", "hit_at": 0.25})
		room._player.state = room._player.State.IDLE
		# 单击伤害有 50% 上限，hurt 已无法直接打死玩家：显式标记红蝶已消耗，
		# 模拟「首次死亡复活后，纯流失烧尽」，才能走到阵亡结算。
		Run.c021_red_butterfly_used = true
		Run.max_hp = Run.calculated_max_hp()
		room._player.max_hp = Run.max_hp
		room._player.hp = 1
		room._player._hurt_invincible = 0.0
		room._player._innate_passive_tick(1.0)
		await get_tree().create_timer(2.6).timeout
		var red_panel = room.get_node_or_null("Settlement")
		_check(red_panel != null, "红蝶纯流失死亡打开阵亡结算")
		_check(Run.last_hit.is_empty(), "红蝶纯流失死亡没有敌方击杀来源")
		if red_panel != null:
			_check(red_panel._enemy == null and red_panel._duel_done, "红蝶自熄不创建敌方对演")
			_check(red_panel._enemy_label() == "命火自熄", "红蝶自熄灭款不显示历史攻击者")
		await _shot("red_butterfly")

		# 重建正式房间，再验证真实敌人补刀仍沿用原敌方对演。
		get_tree().paused = false
		room.queue_free()
		await get_tree().process_frame
		Run.start(Run.MODE_ADVENTURE, "c021", 3)
		room = load("res://scenes/world/room_01.tscn").instantiate()
		add_child(room)
		await get_tree().create_timer(1.0).timeout
		_ink_before = Meta.ink
		# 阵亡路径：先换成银夜再死，验证「再来一局」沿用当前形态（不能掉回默认绯刃）
		room._player.swap_skull("z003")
		p("换形态 -> " + str(room._player.skull_id))
		# 固定实伤条件，避免等待期间受击无敌或银夜 20% 暗夜让测试补刀随机落空。
		room._player.hp = 1
		room._player.state = room._player.State.IDLE
		room._player._hurt_invincible = 0.0
		room._player._hurt_cast_key = ""
		room._player._invincible = false
		room._player._passive_seal_time = 10.0
		var attacker = room._spawner._alive[0] if not room._spawner._alive.is_empty() else null
		var move := {"anim": "skill01", "hit_at": 0.25}
		room._player.hurt(1, Vector2(80, -60), attacker, move)
		p("killed player, hp=%d last_hit=%s" % [room._player.hp, str(Run.last_hit)])
		await get_tree().create_timer(2.6).timeout
		var death_panel = room.get_node_or_null("Settlement")
		_check(not Run.last_hit.is_empty(), "真实敌人致死保留攻击来源")
		if death_panel != null:
			_check(death_panel._enemy != null, "真实敌人致死仍创建敌方对演")
			_check(death_panel._enemy_label() not in ["命火自熄", "无名墨影"], "真实敌人致死显示实际敌人落款")
			death_panel._finish_duel()
			_check_result_fx(death_panel, "lose")
			_check(death_panel._last_hit_fx != null and death_panel._last_hit_fx.sprite != null \
				and death_panel._last_hit_fx.sprite.get("skeleton_data_res") != null, "最后一击创建真实 E50041 SpineSprite")
			if death_panel._last_hit_fx != null:
				var hit_state = death_panel._last_hit_fx.sprite.call("get_animation_state")
				var hit_track = hit_state.call("get_current", 0)
				_check(hit_track != null and str(hit_track.call("get_animation").call("get_name")) == "action", "最后一击使用实测 action 动画")
			var hit_fx_count := 0
			var damage_count := 0
			for child in death_panel.get_children():
				if str(child.name).begins_with("LastHitSpineFX"):
					hit_fx_count += 1
				if str(child.name).begins_with("LastHitDamage"):
					damage_count += 1
			death_panel._finish_duel()
			_check(hit_fx_count == 1, "原命中与跳过路径只保留一个最后一击特效")
			_check(damage_count == (1 if int(Run.last_hit.get("damage", 0)) > 0 else 0), "伤害数字保留且不重复")
			await get_tree().create_timer(0.2, true).timeout
		await _shot("dead")
		_check_ink(false)
		p("阵亡后 Run.skull_id=%s mode=%s difficulty=%d（期望 z003 / adventure / 3）" % [Run.skull_id, Run.mode, Run.difficulty])
		# 结算面板「再来一局」沿用本局模式、难度与当前形态。
		Run.start(Run.mode, Run.skull_id, Run.difficulty)
		p("再来一局 -> skull=%s mode=%s difficulty=%d depth=%d active=%s（期望 z003 / adventure / 3 / 1 / true）" % [Run.skull_id, Run.mode, Run.difficulty, Run.depth, Run.active])

	p("settlement visible=" + str(room.get_node_or_null("Settlement") != null))
	p("DONE checks=%d failed=%d" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	p(("PASS " if ok else "FAIL ") + label)


func _check_result_fx(panel: Node, expected: String) -> void:
	_check(panel != null and panel._result_fx != null and panel._result_fx.sprite != null \
		and panel._result_fx.sprite.get("skeleton_data_res") != null, "结算创建真实 E21013 SpineSprite")
	if panel == null or panel._result_fx == null:
		return
	_check(panel._result_fx.process_mode == Node.PROCESS_MODE_ALWAYS, "结算特效在暂停中继续播放")
	_check(panel._result_fx.position == Vector2(640, 92), "胜负结算特效使用避开文字的同一位置")
	_check(panel._result_anim == expected, "结算使用实测动画 " + expected)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "结算可点击界面恢复自定义鼠标")
	var has_duplicate_title := false
	for label in panel.find_children("*", "Label", true, false):
		if str(label.text) in ["通  关", "阵  亡"]:
			has_duplicate_title = true
	_check(not has_duplicate_title, "胜负特效不再叠加标题文字")
	var state = panel._result_fx.sprite.call("get_animation_state")
	var track = state.call("get_current", 0)
	_check(track != null and str(track.call("get_animation").call("get_name")) == expected, "结算 Spine 当前轨道为 " + expected)


func _check_ink(cleared: bool) -> void:
	var kills := Score.kills
	var rooms := Run.cleared_room_count()
	# 成就解锁的墨锭奖励也计入 Meta.ink，这里一并算进预期
	var ach_ink := 0
	for id in Achievements.session_unlocks():
		ach_ink += int(Achievements.get_def(str(id)).get("ink", 0))
	var expected := 2 + floori(kills / 2.0) + rooms * 5 + (25 if cleared else 0) + 2 * Meta.shop_level("start_ink") + ach_ink
	var actual := Meta.ink - _ink_before
	p("墨锭结算：击杀=%d 已清房间=%d 通关=%s 聚墨=%d 功名奖励=%d 实际=%d 预期=%d（期望一致）" % [kills, rooms, cleared, Meta.shop_level("start_ink"), ach_ink, actual, expected])


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
	var err = img.save_png(OUT_DIR + "settle_" + tag + ".png")
	p("saved " + tag + " err=" + str(err))
