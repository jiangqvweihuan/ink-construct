extends RefCounted

## 玩家身上的 SpineSprite 特效层：常驻护罩 / 觉醒、技能施法特效、
## 时停标记、全屏特效、世界坐标技能。
## 只负责「建 / 收 / 每帧同步」，伤害与状态判定仍留在 player.gd。
## 宿主需提供：state、skull_id、_shield_hits、_awaken_time、_body_fx_scale()、_radius_of()。

const SPINE_FX = preload("res://scripts/systems/spine_fx.gd")

var shield_spine: Node2D = null
var skill_spine: Node2D = null
var awaken_spine: Node2D = null
var silver_awaken_ready := false
var world_skill_spine: Node2D = null
var world_skill_left := 0.0
var stop_targets: Dictionary = {}

var _host: Node2D


func _init(host: Node2D) -> void:
	_host = host


func resolve_anim(fx_id: String, requested: String) -> String:
	var d = SPINE_FX.data(fx_id)
	if d == null:
		return requested
	for candidate in [requested, "action", "action1"]:
		var anim := str(candidate)
		if not anim.is_empty() and d.call("find_animation", anim) != null:
			return anim
	var animations: Array = d.call("get_animations")
	return str(animations[0].call("get_name")) if not animations.is_empty() else requested


func make(parent: Node, fx_id: String, pos: Vector2, anim: String, loop: bool, opts: Dictionary = {}) -> Node2D:
	var actual := opts.duplicate(true)
	actual["anim"] = resolve_anim(fx_id, anim)
	actual["loop"] = loop
	actual["auto_free"] = not loop
	var role := str(actual.get("fx_role", ""))
	actual.erase("fx_role")
	var node := SPINE_FX.attach(parent, fx_id, pos, actual)
	if node != null:
		node.set_meta("fx_id", fx_id)
		node.set_meta("fx_anim", actual["anim"])
		if not role.is_empty():
			node.set_meta("fx_role", role)
	return node


## 挂在玩家自己身上，位置是玩家本地坐标。
func attach(fx_id: String, pos: Vector2, anim: String, loop := false, opts: Dictionary = {}) -> Node2D:
	return make(_host, fx_id, pos, anim, loop, opts)


## 挂在当前场景根下，pos 传世界坐标。
func world(fx_id: String, pos: Vector2, anim: String, loop := false, opts: Dictionary = {}) -> Node2D:
	var host := _host.get_tree().current_scene
	if host == null:
		return null
	var local_pos := pos
	if host is Node2D:
		local_pos = (host as Node2D).to_local(pos)
	return make(host, fx_id, local_pos, anim, loop, opts)


## 参数不能标 Node2D：one-shot 特效自释放后，残留引用传进来会在类型校验处直接报错
func release(node) -> void:
	if is_instance_valid(node) and not node.is_queued_for_deletion():
		node.queue_free()


func clear_skill() -> void:
	release(skill_spine)
	skill_spine = null


func clear_stop_targets() -> void:
	for fx_id in stop_targets.values():
		var node := instance_from_id(int(fx_id))
		if node is Node2D and not node.is_queued_for_deletion():
			release(node)
	stop_targets.clear()


func tick_stop_targets() -> void:
	for target_id in stop_targets.keys():
		var target := instance_from_id(int(target_id))
		var node := instance_from_id(int(stop_targets[target_id]))
		var target_stopped := is_instance_valid(target) and not target.is_queued_for_deletion() \
			and int(target.get("hp")) > 0 and float(target.get("_stop_timer")) > 0.0
		var fx_alive := is_instance_valid(node) and not node.is_queued_for_deletion()
		if target_stopped and fx_alive:
			continue
		stop_targets.erase(target_id)
		if fx_alive:
			node.queue_free()


func attach_stop_target(target: Node2D) -> void:
	var target_id := target.get_instance_id()
	if stop_targets.has(target_id):
		var old_fx := instance_from_id(int(stop_targets[target_id]))
		if is_instance_valid(old_fx) and not old_fx.is_queued_for_deletion():
			return
		stop_targets.erase(target_id)
	var radius := maxf(1.0, _host._radius_of(target))
	var node := make(target, "E54169", Vector2(0.0, -radius * 2.0), "action", true, {
		"height": radius * 4.0, "center": true, "fx_role": "time_stop_target",
	})
	if node != null:
		stop_targets[target_id] = node.get_instance_id()


func has_stopped_target() -> bool:
	for e in _host.get_tree().get_nodes_in_group("enemies"):
		if int(e.get("hp")) > 0 and float(e.get("_stop_timer")) > 0.0:
			return true
	return false


func clear_all() -> void:
	clear_skill()
	clear_stop_targets()
	release(shield_spine)
	release(awaken_spine)
	release(world_skill_spine)
	shield_spine = null
	awaken_spine = null
	silver_awaken_ready = false
	world_skill_spine = null
	world_skill_left = 0.0


func sync_persistent(dead: bool) -> void:
	if _host._shield_hits > 0 and not dead:
		if not is_instance_valid(shield_spine) or shield_spine.is_queued_for_deletion():
			shield_spine = attach("E52025", Vector2(0.0, -64.0), "action1", true,
				{"scale": 0.5 * _host._body_fx_scale(), "fx_role": "shield"})
	else:
		release(shield_spine)
		shield_spine = null
	var awaken_id: String = {"z000": "E100177", "z002": "E100172", "z003": "E21105"}.get(_host.skull_id, "")
	var awaken_visual_ready: bool = _host.skull_id != "z003" or silver_awaken_ready
	if _host._awaken_time > 0.0 and awaken_visual_ready and not awaken_id.is_empty() and not dead:
		if not is_instance_valid(awaken_spine) or awaken_spine.is_queued_for_deletion():
			awaken_spine = attach(awaken_id, Vector2.ZERO if _host.skull_id == "z003" else Vector2(0.0, -64.0), "action", true,
				{"scale": (0.75 if _host.skull_id == "z000" else (1.0 if _host.skull_id == "z002" else 0.25)) * _host._body_fx_scale(),
				"center": _host.skull_id == "z002", "fx_role": "awaken"})
	else:
		release(awaken_spine)
		awaken_spine = null
		if _host.skull_id == "z003" and (_host._awaken_time <= 0.0 or dead):
			silver_awaken_ready = false


func tick(delta: float, dead: bool) -> void:
	tick_stop_targets()
	if world_skill_left > 0.0:
		world_skill_left = maxf(0.0, world_skill_left - delta)
	if is_instance_valid(world_skill_spine) and not world_skill_spine.is_queued_for_deletion():
		if world_skill_left <= 0.0 and not has_stopped_target():
			release(world_skill_spine)
			world_skill_spine = null
	else:
		world_skill_spine = null
		world_skill_left = 0.0
	sync_persistent(dead)


func fullscreen(fx_id: String, anim: String) -> Node2D:
	var center := _host.global_position
	var camera := _host.get_viewport().get_camera_2d()
	if camera != null:
		center = camera.get_screen_center_position()
	return world(fx_id, center, anim, false, {
		"cover": _host.get_viewport().get_visible_rect().size * 1.05,
		"center": true, "fx_role": "full_screen",
	})
