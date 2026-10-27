extends Node2D

## 修复验证探针：
## 1) 玩家被击退的精确时刻 vs 敌人攻击动画 track_time -> 验证命中时机对准钩子甩出帧
## 2) 敌人 state 切换时刻 -> 验证收招是否仍在兜底延迟（ATTACK 应在动画播完当帧退出）

const OUT_DIR := "res://tests/out/"

var _log: FileAccess
var _enemy
var _player
var _t := 0.0
var _shot_idx := 0
var _post_left := 0.0
var _prev_state := -1
var _prev_px := 0.0

func p(msg) -> void:
	print("[V] ", msg)
	if _log:
		_log.store_line("[V] " + str(msg))
		_log.flush()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/verify_fix.log", FileAccess.WRITE)
	get_window().size = Vector2i(1280, 720)

	var ground := StaticBody2D.new()
	ground.position = Vector2(640, 660)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(1280, 80)
	shape.shape = rect
	ground.add_child(shape)
	add_child(ground)

	_player = load("res://scenes/player/player.tscn").instantiate()
	_player.position = Vector2(560, 560)
	add_child(_player)
	_enemy = load("res://scenes/enemies/c016.tscn").instantiate()
	_enemy.position = Vector2(640, 560)
	add_child(_enemy)

	await get_tree().create_timer(12.0).timeout
	p("ALL DONE")
	get_tree().quit()

func _physics_process(delta: float) -> void:
	if _enemy == null or _enemy._anim_state == null:
		return
	_t += delta
	var cur = _enemy._anim_state.call("get_current", 0)
	var anim_name := "NULL"
	var tt := -1.0
	if cur != null:
		var a = cur.call("get_animation")
		anim_name = str(a.call("get_name")) if a != null else "?"
		tt = cur.call("get_track_time")

	# state 切换：收招时 ATTACK->IDLE 的 tt 应贴近动画全长（2.167/1.75），提前/延后都是 bug
	if _enemy.state != _prev_state:
		p("STATE %d -> %d  t=%.3f anim=%s track=%.3f" % [_prev_state, _enemy.state, _t, anim_name, tt])
		_prev_state = _enemy.state

	# 玩家击退检测：站桩时 px 不变，被命中的当帧 px 开始滑动
	var px: float = _player.global_position.x
	if absf(px - _prev_px) > 2.0 and _enemy.state == 3:
		p("HIT t=%.3f enemy_anim=%s track=%.3f px=%.1f" % [_t, anim_name, tt, px])
	_prev_px = px

	if _enemy.state == 3:
		_post_left = 0.6
		_shot_idx += 1
		_shot("atk_%s_%03d" % [anim_name, _shot_idx])
	elif _post_left > 0.0:
		_post_left -= delta
		_shot_idx += 1
		_shot("post_%03d" % _shot_idx)

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "v2_" + tag + ".png")
