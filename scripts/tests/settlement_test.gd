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
		# 通关路径改了：三关全过进 Boss 房，斩杀 Boss 才出通关结算。
		# 先 Run.start() 再设房间号，房间 _ready 就不会重开新局覆盖掉
		Run.start()
		Run.room_index = Run.ROOMS.size() # Boss 房
		Run.boss_id = "_debug"
	add_child(room)
	await get_tree().create_timer(1.0).timeout

	if test_clear:
		# 玩家拉满血防止被 Boss 反杀；变身期无敌，分阶段持续打到死
		room._player.max_hp = 99
		room._player.hp = 99
		var waited := 0.0
		while room.get_node_or_null("Settlement") == null and waited < 120.0:
			var b = room._boss
			if is_instance_valid(b) and b.hp > 0:
				b.take_damage(4, b.global_position.x - 10.0)
			await get_tree().create_timer(0.4).timeout
			waited += 0.4
		p("cleared, waited=%.1f" % waited)
		await get_tree().create_timer(1.0).timeout
		await _shot("clear")
	else:
		# 阵亡路径：先换成银夜再死，验证「再来一局」沿用当前形态（不能掉回默认双刺）
		room._player.swap_skull("z003")
		p("换形态 -> " + str(room._player.skull_id))
		# 受伤无敌 0.8s 会让连打大部分落空，直接压到 1 血再补一刀走阵亡路径
		room._player.hp = 1
		room._player.hurt(1, Vector2(80, -60))
		p("killed player, hp=" + str(room._player.hp))
		await get_tree().create_timer(1.8).timeout
		await _shot("dead")
		p("阵亡后 Run.skull_id=%s mode=%s（期望 z003 / adventure）" % [Run.skull_id, Run.mode])
		# 结算面板「再来一局」就是这两步：先按本局模式+当前形态重开，再重载场景
		Run.start(Run.mode, Run.skull_id)
		p("再来一局 -> skull=%s mode=%s depth=%d active=%s（期望 z003 / adventure / 1 / true）" % [Run.skull_id, Run.mode, Run.depth, Run.active])

	p("settlement visible=" + str(room.get_node_or_null("Settlement") != null))
	p("ALL DONE")
	get_tree().quit()

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + "settle_" + tag + ".png")
	p("saved " + tag + " err=" + str(err))
