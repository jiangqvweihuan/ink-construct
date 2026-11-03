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
		_check_ink(true)
	else:
		# 先让敌人触发红蝶留下历史受击，再完全因流失死亡：结算不得重演这名敌人。
		var red_attacker = room._spawner._alive[0] if not room._spawner._alive.is_empty() else null
		room._player.hurt(20, Vector2.ZERO, red_attacker, {"anim": "skill01", "hit_at": 0.25})
		room._player.state = room._player.State.IDLE
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
		# 阵亡路径：先换成银夜再死，验证「再来一局」沿用当前形态（不能掉回默认双刺）
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


func _check_ink(cleared: bool) -> void:
	var kills := Score.kills
	var rooms := Run.cleared_room_count()
	var expected := 2 + floori(kills / 2.0) + rooms * 5 + (25 if cleared else 0) + 2 * Meta.shop_level("start_ink")
	var actual := Meta.ink - _ink_before
	p("墨锭结算：击杀=%d 已清房间=%d 通关=%s 聚墨=%d 实际=%d 预期=%d（期望一致）" % [kills, rooms, cleared, Meta.shop_level("start_ink"), actual, expected])


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + "settle_" + tag + ".png")
	p("saved " + tag + " err=" + str(err))
