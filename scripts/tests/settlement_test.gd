extends Node

## 结算冒烟测试：test_clear=true 杀光小怪看通关面板，否则打死玩家看阵亡面板

@export var test_clear := false

const OUT_DIR := "res://tests/out/"

var _log: FileAccess

func p(msg) -> void:
	print("[S] ", msg)
	if _log:
		_log.store_line("[S] " + str(msg))
		_log.flush()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/settlement_test.log", FileAccess.WRITE)

	var room = load("res://scenes/world/room_01.tscn").instantiate()
	if test_clear:
		# 无归通关：连续斩杀两只不同 Boss，验证中间不弹强化、结算留下双印。
		Run.start(Run.MODE_ADVENTURE, "c021", Run.DIFFICULTIES.size() - 1)
		Run.room_index = Run.ROOMS.size()
		Run.boss_queue = ["_debug", "c001"]
		Run.boss_id = "_debug"
	else:
		Run.start(Run.MODE_ADVENTURE, "c021", 3)
	add_child(room)
	await get_tree().create_timer(1.0).timeout

	if test_clear:
		# 玩家拉满血防止被 Boss 反杀；变身期无敌，分阶段持续打到死
		room._player.max_hp = 99
		room._player.hp = 99
		var waited := 0.0
		var saw_second := false
		while room.get_node_or_null("Settlement") == null and waited < 120.0:
			room._player.max_hp = 99
			room._player.hp = 99
			room._player._invincible = true
			var b = room._boss
			if is_instance_valid(b) and b.hp > 0:
				b.take_damage(8, b.global_position.x - 10.0)
			if is_instance_valid(b) and str(b.type_id) == "c001" and not saw_second:
				saw_second = true
				p("第二只 Boss 已登场：phase=%d，强化面板=%s（期望 1 / false）" % [Run.boss_phase, room.get_node_or_null("Upgrade") != null])
			await get_tree().create_timer(0.4).timeout
			waited += 0.4
		p("cleared, waited=%.1f second=%s defeated=%s（期望双 Boss）" % [waited, saw_second, str(Run.boss_defeated)])
		await get_tree().create_timer(1.0).timeout
		await _shot("clear")
	else:
		# 阵亡路径：先换成银夜再死，验证「再来一局」沿用当前形态（不能掉回默认双刺）
		room._player.swap_skull("z003")
		p("换形态 -> " + str(room._player.skull_id))
		# 受伤无敌 0.8s 会让连打大部分落空，直接压到 1 血再补一刀走阵亡路径
		room._player.hp = 1
		var attacker = room._spawner._alive[0] if not room._spawner._alive.is_empty() else null
		var move := {"anim": "skill01", "hit_at": 0.25}
		room._player.hurt(1, Vector2(80, -60), attacker, move)
		p("killed player, hp=%d last_hit=%s" % [room._player.hp, str(Run.last_hit)])
		await get_tree().create_timer(2.6).timeout
		await _shot("dead")
		p("阵亡后 Run.skull_id=%s mode=%s difficulty=%d（期望 z003 / adventure / 3）" % [Run.skull_id, Run.mode, Run.difficulty])
		# 结算面板「再来一局」沿用本局模式、难度与当前形态。
		Run.start(Run.mode, Run.skull_id, Run.difficulty)
		p("再来一局 -> skull=%s mode=%s difficulty=%d depth=%d active=%s（期望 z003 / adventure / 3 / 1 / true）" % [Run.skull_id, Run.mode, Run.difficulty, Run.depth, Run.active])

	p("settlement visible=" + str(room.get_node_or_null("Settlement") != null))
	p("ALL DONE")
	get_tree().quit()

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + "settle_" + tag + ".png")
	p("saved " + tag + " err=" + str(err))
