extends Node2D

const OUT_DIR := "res://tests/out/"

var _log: FileAccess

func p(msg) -> void:
	print("[T] ", msg)
	if _log:
		_log.store_line("[T] " + str(msg))
		_log.flush()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/test.log", FileAccess.WRITE)
	get_window().size = Vector2i(1280, 720)

	var bg := ColorRect.new()
	bg.color = Color(0.949, 0.918, 0.847)
	bg.size = Vector2(1280, 720)
	bg.z_index = -10
	add_child(bg)

	_dump_methods("SpineSprite")
	_dump_methods("SpineAnimationState")

	var player = _make_sprite("res://art/characters/player/", "res://art/characters/player/c021_data.tres", Vector2(400, 580))
	var enemy = _make_sprite("res://art/characters/enemies/c016/", "res://art/characters/enemies/c016/c016_data.tres", Vector2(920, 580))

	await get_tree().create_timer(0.5).timeout
	await _run_anims(player, "c021")
	await _run_anims(enemy, "c016")

	p("ALL DONE")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

func _dump_methods(cls: String) -> void:
	var names: Array[String] = []
	for m in ClassDB.class_get_method_list(cls, true):
		names.append(m["name"])
	p("methods of " + cls + ": " + ", ".join(names))

func _make_sprite(dir: String, tres_path: String, pos: Vector2):
	var data = load(tres_path)
	p("load tres " + tres_path + " => " + str(data))
	if data != null:
		p("  is_skeleton_data_loaded=" + str(data.call("is_skeleton_data_loaded")))
	if data == null or not data.call("is_skeleton_data_loaded"):
		p("  tres 不可用，改为代码构建")
		data = ClassDB.instantiate("SpineSkeletonDataResource")
		var atlas = load(dir + "skeleton.atlas")
		var skel = load(dir + "skeleton.skel")
		p("  atlas=" + str(atlas) + " skel=" + str(skel))
		data.call("set_atlas_res", atlas)
		data.call("set_skeleton_file_res", skel)
		p("  built, is_skeleton_data_loaded=" + str(data.call("is_skeleton_data_loaded")))

	var names: Array = []
	for a in data.call("get_animations"):
		names.append(a.call("get_name"))
	p(dir + " anims=" + str(names))
	p(dir + " bounds x=" + str(data.call("get_x")) + " y=" + str(data.call("get_y")) + " w=" + str(data.call("get_width")) + " h=" + str(data.call("get_height")))

	var sprite = ClassDB.instantiate("SpineSprite")
	add_child(sprite)
	sprite.set("skeleton_data_res", data)
	var h: float = data.call("get_height")
	var s: float = 1.0
	if h > 0.0:
		s = clampf(300.0 / h, 0.05, 2.0)
	sprite.scale = Vector2(s, s)
	sprite.position = pos
	p(dir + " sprite scale=" + str(s))
	return sprite

func _run_anims(sprite, tag: String) -> void:
	if sprite == null:
		p(tag + ": sprite is null, skip")
		return
	var state = sprite.call("get_animation_state")
	p(tag + " state=" + str(state))
	if state == null:
		return
	var data = sprite.get("skeleton_data_res")
	for a in data.call("get_animations"):
		var anim_name: String = a.call("get_name")
		state.call("set_animation", anim_name, true, 0)
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var img = get_viewport().get_texture().get_image()
		var err = img.save_png(OUT_DIR + tag + "_" + anim_name + ".png")
		p(tag + " saved " + anim_name + " err=" + str(err))
