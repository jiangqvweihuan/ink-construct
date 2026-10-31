extends Node2D

## 刀客动画切换对照：直接驱动正式 c016._play，采样渲染后的骨骼世界坐标。

var _log: FileAccess
var _enemy
var _last_anim := ""
var _last_track_time := -1.0
var _last_pose: Dictionary = {}


func p(msg) -> void:
	print("[D] ", msg)
	if _log:
		_log.store_line("[D] " + str(msg))
		_log.flush()


func _ready() -> void:
	_log = FileAccess.open("res://tests/twitch_test.log", FileAccess.WRITE)
	get_window().size = Vector2i(1280, 720)
	_enemy = load("res://scenes/enemies/c016.tscn").instantiate()
	_enemy.position = Vector2(640, 560)
	add_child(_enemy)
	_enemy.set_physics_process(false)
	RenderingServer.frame_post_draw.connect(_sample_animation_frame)

	for spec in [
		["stand", true], ["skill01", false], ["run", true],
		["stand", true], ["skill01", false], ["stand", true],
		["speed_run", true], ["skill04", false], ["run", true],
	]:
		_enemy._play(str(spec[0]), bool(spec[1]))
		await get_tree().create_timer(0.7).timeout
	p("ALL DONE")
	get_tree().quit()


func _sample_animation_frame() -> void:
	if _enemy == null or _enemy._anim_state == null:
		return
	var current = _enemy._anim_state.call("get_current", 0)
	if current == null:
		return
	var animation = current.call("get_animation")
	var anim_name := str(animation.call("get_name")) if animation != null else "?"
	var track_time := float(current.call("get_track_time"))
	var pose := _bone_pose()
	var largest := 0.0
	var delta_bone := -1
	for i in pose:
		if not _last_pose.has(i):
			continue
		var distance := Vector2(pose[i][0], pose[i][1]).distance_to(Vector2(_last_pose[i][0], _last_pose[i][1]))
		if distance > largest:
			largest = distance
			delta_bone = i
	if anim_name != _last_anim or not is_equal_approx(track_time, _last_track_time):
		p("anim=%s track=%.3f bone_delta=%.2f bone=%d" % [anim_name, track_time, largest, delta_bone])
	_last_anim = anim_name
	_last_track_time = track_time
	_last_pose = pose


func _bone_pose() -> Dictionary:
	var pose := {}
	var bones = _enemy.sprite.call("get_skeleton").call("get_bones")
	for i in bones.size():
		var bone = bones[i]
		pose[i] = [float(bone.call("get_world_x")), float(bone.call("get_world_y"))]
	return pose
