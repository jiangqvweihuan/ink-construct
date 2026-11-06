extends Node2D

## Spine 4.2 特效统一入口：按资源 ID 加载、缓存骨架，支持跟随父节点、暂停 UI 与定时销毁。
## spawn/attach 的 pos 都是父节点本地坐标；持续特效由状态所有者保存返回值并 queue_free。

static var _data_cache: Dictionary = {}
static var _self_script: GDScript

var sprite: Node2D
var _lifetime := -1.0
var _base_scale := Vector2.ONE
var _fit_height := 0.0
var _fit_width := 0.0
var _fit_cover := Vector2.ZERO
var _flip := false
var _offset := Vector2.ZERO
var _center := false
var _bottom := false


static func data(fx_id: String):
	var id := fx_id.to_upper()
	if _data_cache.has(id):
		return _data_cache[id]
	var base := "res://art/fx/spine/%s/%s" % [id, id]
	var atlas = ClassDB.instantiate("SpineAtlasResource")
	var atlas_err := int(atlas.call("load_from_atlas_file", base + ".atlas")) if atlas != null else ERR_CANT_CREATE
	var skel = load(base + ".skel")
	if atlas_err != OK or skel == null:
		push_error("SpineFX: 资源加载失败 " + base)
		return null
	var d = ClassDB.instantiate("SpineSkeletonDataResource")
	d.call("set_atlas_res", atlas)
	d.call("set_skeleton_file_res", skel)
	if not d.call("is_skeleton_data_loaded"):
		push_error("SpineFX: 骨架数据无效 " + base)
		return null
	d.call("set_default_mix", 0.0)
	_data_cache[id] = d
	return d


static func animation_names(fx_id: String) -> Array[String]:
	var out: Array[String] = []
	var d = data(fx_id)
	if d == null:
		return out
	for a in d.call("get_animations"):
		out.append(str(a.call("get_name")))
	return out


static func spawn(parent: Node, fx_id: String, pos: Vector2, opts: Dictionary = {}) -> Node2D:
	return _make(parent, fx_id, pos, opts)


static func attach(parent: Node, fx_id: String, pos: Vector2, opts: Dictionary = {}) -> Node2D:
	return _make(parent, fx_id, pos, opts)


static func _make(parent: Node, fx_id: String, pos: Vector2, opts: Dictionary) -> Node2D:
	var d = data(fx_id)
	if parent == null or d == null:
		return null
	if _self_script == null:
		_self_script = load("res://scripts/systems/spine_fx.gd")
	var f: Node2D = _self_script.new()
	f.position = pos
	f.z_index = int(opts.get("z", 20))
	f.modulate = opts.get("mod", Color.WHITE)
	f.process_mode = Node.PROCESS_MODE_ALWAYS if bool(opts.get("always", false)) else Node.PROCESS_MODE_INHERIT
	parent.add_child(f)
	f.sprite = ClassDB.instantiate("SpineSprite")
	if f.sprite == null: # Spine 插件缺失/实例化失败时安全放弃，不空引用
		f.queue_free()
		return null
	f.sprite.process_mode = f.process_mode
	f.add_child(f.sprite)
	f.sprite.set("skeleton_data_res", d)
	# 统一由本节点推进，避免 SpineSprite 自动更新与 bounds 测量错开一帧。
	f.sprite.call("set_update_mode", 2)
	var raw_scale: Variant = opts.get("scale", 1.0)
	f._base_scale = raw_scale if raw_scale is Vector2 else Vector2.ONE * float(raw_scale)
	f._fit_height = float(opts.get("height", 0.0))
	f._fit_width = float(opts.get("width", 0.0))
	f._fit_cover = opts.get("cover", Vector2.ZERO)
	f._flip = bool(opts.get("flip", false))
	f._offset = opts.get("offset", Vector2.ZERO)
	f._center = bool(opts.get("center", false))
	f._bottom = bool(opts.get("bottom", false))
	# 首帧等待时只设透明：零缩放或隐藏会让部分 4.2 素材停止产出有效 bounds。
	f.sprite.scale = f._base_scale
	f.sprite.self_modulate = Color(1, 1, 1, 0) if f._requires_bounds() else Color.WHITE
	f.sprite.position = f._offset
	var names: Array = []
	for a in d.call("get_animations"):
		names.append(str(a.call("get_name")))
	var anim := str(opts.get("anim", names[0] if not names.is_empty() else ""))
	if not names.has(anim) and not names.is_empty():
		push_warning("SpineFX: %s 无动画 %s，改用 %s" % [fx_id, anim, names[0]])
		anim = names[0]
	f.play(anim, bool(opts.get("loop", false)), float(opts.get("speed", 1.0)), bool(opts.get("auto_free", true)))
	return f


func play(anim: String, loop := false, speed := 1.0, auto_free := true) -> void:
	_lifetime = -1.0
	if sprite == null or anim.is_empty():
		if auto_free and not loop:
			queue_free()
		return
	var state = sprite.call("get_animation_state")
	var entry = state.call("set_animation", anim, loop, 0)
	if entry != null:
		entry.call("set_time_scale", speed)
	# 切动画后立即测量；首帧为空时先隐藏，后续帧再适配，避免原始尺寸闪现。
	sprite.call("update_skeleton", 0.0)
	sprite.call("force_update_transform")
	_apply_scale()
	if auto_free and not loop:
		var d = sprite.get("skeleton_data_res")
		var a = d.call("find_animation", anim)
		var duration := float(a.call("get_duration")) if a != null else 1.0
		_lifetime = maxf(0.05, duration / maxf(0.01, absf(speed)))


func _requires_bounds() -> bool:
	return _fit_height > 0.0 or _fit_width > 0.0 \
		or (_fit_cover.x > 0.0 and _fit_cover.y > 0.0) or _center or _bottom


static func _valid_bounds(bounds: Rect2) -> bool:
	return is_finite(bounds.position.x) and is_finite(bounds.position.y) \
		and is_finite(bounds.size.x) and is_finite(bounds.size.y) \
		and bounds.size.x > 0.001 and bounds.size.y > 0.001


func _apply_scale() -> void:
	if sprite == null:
		return
	var sc := _base_scale
	var target := _fit_height if _fit_height > 0.0 else _fit_width
	var bounds := Rect2()
	if _requires_bounds():
		bounds = sprite.call("get_skeleton").call("get_bounds")
		if not _valid_bounds(bounds):
			sprite.self_modulate = Color(1, 1, 1, 0)
			sprite.scale = _base_scale
			sprite.position = _offset
			return
	sprite.self_modulate = Color.WHITE
	if _fit_cover.x > 0.0 and _fit_cover.y > 0.0:
		sc = Vector2.ONE * maxf(_fit_cover.x / bounds.size.x, _fit_cover.y / bounds.size.y)
	elif target > 0.0:
		var measured := bounds.size.y if _fit_height > 0.0 else bounds.size.x
		sc = Vector2.ONE * (target / measured)
	if _flip:
		sc.x = -absf(sc.x)
	sprite.scale = sc
	if _center:
		var center := bounds.get_center()
		sprite.position = _offset - Vector2(center.x * sc.x, center.y * sc.y)
	elif _bottom:
		# 底部对齐：把动画当前可见范围的下沿钉在节点位置，落地/喷涌类特效不会陷进地面
		sprite.position = _offset - Vector2(0.0, bounds.end.y * sc.y)
	else:
		sprite.position = _offset


func _process(delta: float) -> void:
	if sprite != null:
		sprite.call("update_skeleton", delta)
		sprite.call("force_update_transform")
		if _requires_bounds():
			_apply_scale()
	if _lifetime < 0.0:
		return
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
