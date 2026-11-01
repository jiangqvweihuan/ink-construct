extends CanvasLayer

## 指定 Boss 房先导：黑底、双方名字与真实骨架对峙；其余 Boss 保持旧登场。

signal finished

const Skulls := preload("res://scripts/player/skulls.gd")
const BossTypes := preload("res://scripts/enemies/boss_types.gd")
const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.42, 0.40, 0.36)

var _player: Node2D
var _boss: Node2D
var _finished := false


func setup(player: Node2D, boss: Node2D) -> void:
	_player = player
	_boss = boss


func _ready() -> void:
	layer = 30
	if _player == null or _boss == null:
		_finish()
		return
	_player.set_physics_process(false)
	_boss.set_physics_process(false)
	_player.hide()
	_boss.hide()

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	_make_platform(root, Vector2(70, 558), Vector2(440, 112))
	_make_platform(root, Vector2(748, 548), Vector2(474, 122))
	var profile: Dictionary = Skulls.get_profile(str(_player.get("skull_id")))
	_make_label(root, str(profile.get("name", profile.get("label", "无名者"))), Vector2(62, 54), Vector2(440, 72), 42, HORIZONTAL_ALIGNMENT_LEFT)
	_make_label(root, str(_boss.get("boss_label")), Vector2(818, 54), Vector2(440, 72), 46, HORIZONTAL_ALIGNMENT_RIGHT)
	_make_label(root, "VS", Vector2(510, 166), Vector2(260, 180), 112, HORIZONTAL_ALIGNMENT_CENTER).add_theme_color_override("font_color", DIM)

	_make_preview(root, load(str(profile["data"])), float(profile.get("scale", 0.394)) * 1.35,
		Vector2(292, 590), str((profile.get("anim", {}) as Dictionary).get("idle", "stand")), true, false)
	var intro: Dictionary = BossTypes.get_boss(str(_boss.get("type_id"))).get("intro", {"anim": "skill01", "loop": false})
	var intro_anim := str(intro.get("anim", "skill01"))
	var duration := float(_boss.get("_anim_durations").get(intro_anim, 2.2))
	_make_preview(root, _boss.get("sprite").get("skeleton_data_res"), float(_boss.get("_scale")) * 0.9,
		Vector2(984, 600), intro_anim, bool(intro.get("loop", false)), true)
	await get_tree().create_timer(maxf(1.2, duration)).timeout
	_finish()


func _make_preview(root: Control, data, view_scale: float, pos: Vector2, anim: String, loop: bool, flip: bool) -> void:
	if data == null:
		return
	var sprite = ClassDB.instantiate("SpineSprite")
	root.add_child(sprite)
	sprite.set("skeleton_data_res", data)
	sprite.scale = Vector2(-view_scale if flip else view_scale, view_scale)
	sprite.position = pos
	var state = sprite.call("get_animation_state")
	state.call("set_animation", anim, loop, 0)


func _make_label(root: Control, text: String, pos: Vector2, size: Vector2, font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = size
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", PAPER)
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	return label


func _make_platform(root: Control, pos: Vector2, size: Vector2) -> void:
	var platform := Polygon2D.new()
	platform.polygon = PackedVector2Array([
		Vector2(0, size.y * 0.35), Vector2(size.x * 0.12, 0),
		Vector2(size.x * 0.86, size.y * 0.05), Vector2(size.x, size.y * 0.42),
		Vector2(size.x * 0.9, size.y * 0.82), Vector2(size.x * 0.18, size.y),
	])
	platform.position = pos
	platform.color = Color(0.24, 0.20, 0.15, 0.72)
	root.add_child(platform)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(_player):
		_player.show()
		_player.set_physics_process(true)
	if is_instance_valid(_boss):
		_boss.show()
		_boss.set_physics_process(true)
		_boss.call("finish_entrance")
	finished.emit()
	queue_free()
