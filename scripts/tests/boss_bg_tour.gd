extends Node

## Boss 房背景巡游：五个形态挨个进 Boss 房，登场演出中段截图，供快速浏览选片。
## 不打战斗，看完即走；产物在 tests/out/bg_tour_<id>.png

const OUT_DIR := "res://tests/out/"
const IDS := ["c009", "c015a1", "c001", "c008", "c032"]


func p(msg) -> void:
	print("[T] ", msg)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	Run.start()
	Run.room_index = Run.ROOMS.size() # 直接 Boss 房
	for id in IDS:
		Run.boss_id = id
		var room = load("res://scenes/world/room_01.tscn").instantiate()
		add_child(room)
		await get_tree().create_timer(0.5).timeout
		room._player.max_hp = 99
		room._player.hp = 99
		# 等登场动作进入中段（落款还在、Boss 姿态展开），再收稳镜头截图
		await get_tree().create_timer(1.8).timeout
		# 登场运镜时长 = chuchang 时长+0.5，每个 Boss 都不一样；截图前强制收稳，
		# 否则拍到的是 zoom 中途画面，背景位置不是稳态，量地面线全白搭
		if Feel._zoom_tween != null and Feel._zoom_tween.is_valid():
			Feel._zoom_tween.kill()
		if Feel._cam != null and is_instance_valid(Feel._cam):
			Feel._cam.zoom = Vector2.ONE
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img = get_viewport().get_texture().get_image()
		var err = img.save_png(OUT_DIR + "bg_tour_" + id + ".png")
		p("saved " + id + " err=" + str(err))
		remove_child(room)
		room.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame # 等旧房间彻底释放，避免两房并存
	p("ALL DONE")
	get_tree().quit()
