extends RefCounted

## 为缺少部分骨骼关键帧的 Spine 动画补齐视觉交叉淡化。
## 自动更新会先写出一个未混合的第 0 帧；因此由调用方把 set_animation 与 update(0)
## 放进同一帧，再从切换前的整副局部骨骼姿势插值到 Spine 当前姿势。

const POSE_PROPERTIES := ["x", "y", "rotation", "scale_x", "scale_y", "shear_x", "shear_y"]
const MANUAL_UPDATE_MODE := 2

var _sprite
var _old_pose: Dictionary = {}
var _clock := 0.0
var _duration := 0.2
var _hold_frame := false


func _init(sprite) -> void:
	_sprite = sprite
	_sprite.call("set_update_mode", MANUAL_UPDATE_MODE)


func capture() -> void:
	_old_pose.clear()
	if _sprite == null or not is_instance_valid(_sprite):
		return
	var bones = _sprite.call("get_skeleton").call("get_bones")
	for i in bones.size():
		var bone = bones[i]
		var pose := {}
		for property in POSE_PROPERTIES:
			pose[property] = float(bone.call("get_" + property))
		_old_pose[i] = pose
	_clock = 0.0
	_hold_frame = true


func update(delta: float) -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	_sprite.call("update_skeleton", delta)
	if not _old_pose.is_empty():
		if _hold_frame:
			_hold_frame = false
		else:
			_clock += delta
		_apply_pose()
	_sprite.call("force_update_transform")


func _apply_pose() -> void:
	var skeleton = _sprite.call("get_skeleton")
	var bones = skeleton.call("get_bones")
	var weight := clampf(_clock / _duration, 0.0, 1.0)
	for i in _old_pose:
		var bone = bones[i]
		var old: Dictionary = _old_pose[i]
		for property in POSE_PROPERTIES:
			var value := lerpf(float(old[property]), float(bone.call("get_" + property)), weight)
			bone.call("set_" + property, value)
	skeleton.call("update_world_transform", 0)
	if weight >= 1.0:
		_old_pose.clear()
