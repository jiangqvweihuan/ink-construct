extends Node2D

## 小怪技能抽搐专项调试：玩家站桩，0.05s 轮询小怪动画轨道，攻击期间 0.1s 截图

const OUT_DIR := "res://tests/out/"

var _log: FileAccess
var _enemy
var _t := 0.0
var _shot_idx := 0
var _post_left := 0.0

func p(msg) -> void:
	print("[D] ", msg)
	if _log:
		_log.store_line("[D] " + str(msg))
		_log.flush()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/twitch_test.log", FileAccess.WRITE)
	get_window().size = Vector2i(1280, 720)

	var ground := StaticBody2D.new()
	ground.position = Vector2(640, 660)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(1280, 80)
	shape.shape = rect
	ground.add_child(shape)
	add_child(ground)

	var player = load("res://scenes/player/player.tscn").instantiate()
	player.position = Vector2(560, 560)
	add_child(player)
	_enemy = load("res://scenes/enemies/c016.tscn").instantiate()
	_enemy.position = Vector2(640, 560)
	add_child(_enemy)

	# 打印各动画真实时长，确认 skill02 到底多长
	var data = load("res://art/characters/enemies/c016/c016_data.tres")
	for n in ["skill01", "skill02", "stand", "speed_run"]:
		var a = data.call("find_animation", n)
		if a != null:
			p("ANIM %s duration=%.3f" % [n, a.call("get_duration")])
		else:
			p("ANIM %s NOT FOUND" % n)

	# 探 mix API：SpineAnimationState / sprite / data 三处都找
	var st = _enemy._anim_state
	for m in ["set_default_mix", "get_default_mix", "set_mix", "get_data", "get_tracks"]:
		p("API state.%s = %s" % [m, str(st.has_method(m))])
	var sp = _enemy.sprite
	for m in ["set_default_mix", "get_default_mix", "set_mix"]:
		p("API sprite.%s = %s" % [m, str(sp.has_method(m))])
	for prop in sp.get_property_list():
		if str(prop.name).contains("mix"):
			p("PROP sprite.%s = %s" % [prop.name, str(sp.get(prop.name))])
	for m in ["set_default_mix", "set_mix"]:
		p("API data.%s = %s" % [m, str(data.has_method(m))])
	for prop in data.get_property_list():
		if str(prop.name).contains("mix"):
			p("PROP data.%s = %s" % [prop.name, str(data.get(prop.name))])

	await get_tree().create_timer(7.0).timeout
	p("ALL DONE")
	get_tree().quit()

func _physics_process(delta: float) -> void:
	if _enemy == null or _enemy._anim_state == null:
		return
	_t += delta
	var cur = _enemy._anim_state.call("get_current", 0)
	var anim_name := "NULL"
	var tt := -1.0
	var complete := false
	var root_x := -9999.0
	if _enemy.sprite != null:
		var sk = _enemy.sprite.call("get_skeleton")
		if sk != null:
			var bone = sk.call("find_bone", "root")
			if bone != null:
				root_x = bone.call("get_world_x")
	if cur != null:
		var a = cur.call("get_animation")
		anim_name = str(a.call("get_name")) if a != null else "?"
		tt = cur.call("get_track_time")
		complete = cur.call("is_complete")
	p("t=%.2f state=%d anim=%s track=%.2f complete=%s rootx=%.2f ex=%.2f" % [_t, _enemy.state, anim_name, tt, str(complete), root_x, _enemy.global_position.x])
	# 攻击期间每帧截图；收招后 0.5s 内继续每帧截图，抓切换瞬间的姿态跳变
	if _enemy.state == 3: # ATTACK
		_post_left = 0.5
		_shot_idx += 1
		_shot("atk_%02d" % _shot_idx)
	elif _post_left > 0.0:
		_post_left -= delta
		_shot_idx += 1
		_shot("post_%02d" % _shot_idx)

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "tw_" + tag + ".png")
