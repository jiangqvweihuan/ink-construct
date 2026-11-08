extends CanvasLayer

## 正式 Boss 房统一先导：黑底、双方名字与真实骨架对峙；未配专属入场动画时用待机。

signal finished

const Skulls := preload("res://scripts/player/skulls.gd")
const BossTypes := preload("res://scripts/enemies/boss_types.gd")
const SpineFX := preload("res://scripts/systems/spine_fx.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const PAPER := Color(0.949, 0.918, 0.847)

var _players: Array = []
var _boss: Node2D
var _duel_fx: Node2D
var _finished := false


func setup(player: Node2D, boss: Node2D) -> void:
	setup_many([player], boss)


## 多人对峙：把当前在场的所有玩家一起拉进画面，站位按人数自动分栏。
func setup_many(players: Array, boss: Node2D) -> void:
	_players = []
	for p in players:
		if is_instance_valid(p):
			_players.append(p)
	_boss = boss


func _ready() -> void:
	layer = 30
	if _players.is_empty() or _boss == null:
		_finish()
		return
	for p in _players:
		p.set_physics_process(false)
		p.hide()
	_boss.set_physics_process(false)
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
	UiKit.fit_layer(self, [bg])

	_layout_players(root)
	_make_platform(root, Vector2(748, 548), Vector2(474, 122))
	_make_label(root, str(_boss.get("boss_label")), Vector2(818, 54), Vector2(440, 72), 46, HORIZONTAL_ALIGNMENT_RIGHT)
	_duel_fx = SpineFX.spawn(root, "E21022", Vector2(640, 334), {
		"anim": "action", "width": 470.0, "z": 1, "auto_free": false, "mod": Color(1, 1, 1, 0.88),
	})
	if _duel_fx != null:
		_duel_fx.name = "BossDuelSpineFX"

	var boss_anims: Dictionary = _boss.get("_anim_map")
	var idle_anim := str(boss_anims.get("idle", "stand"))
	var intro: Dictionary = BossTypes.get_boss(str(_boss.get("type_id"))).get("intro", {"anim": idle_anim, "loop": true})
	var intro_anim := str(intro.get("anim", idle_anim))
	# Boss 脚本可能尚未完成骨架挂载：取不到就按默认时长/默认缩放走，绝不空引用。
	var durations_v = _boss.get("_anim_durations")
	var durations: Dictionary = durations_v if durations_v is Dictionary else {}
	var duration := float(durations.get(intro_anim, 2.2))
	var boss_sprite = _boss.get("sprite")
	var boss_skin = boss_sprite.get("skeleton_data_res") if is_instance_valid(boss_sprite) else null
	var scale_v = _boss.get("_scale")
	var boss_scale := float(scale_v) if (scale_v is int or scale_v is float) else 1.0
	_make_preview(root, boss_skin, boss_scale * 0.9,
		Vector2(984, 600), intro_anim, bool(intro.get("loop", false)), true)
	await get_tree().create_timer(maxf(1.2, duration)).timeout
	_finish()


## 左侧玩家栏：单人沿用原来的大立绘；多人按人数均分，逐人配名字与骨架预览。
func _layout_players(root: Control) -> void:
	var n := _players.size()
	if n <= 1:
		var only = _players[0]
		_make_platform(root, Vector2(70, 558), Vector2(440, 112))
		var profile: Dictionary = Skulls.get_profile(str(only.get("skull_id")))
		_make_label(root, str(profile.get("name", profile.get("label", "无名者"))),
			Vector2(62, 54), Vector2(440, 72), 42, HORIZONTAL_ALIGNMENT_LEFT)
		_make_preview(root, load(str(profile["data"])), float(profile.get("scale", 0.394)) * 1.35,
			Vector2(292, 590), str((profile.get("anim", {}) as Dictionary).get("idle", "stand")), true, false)
		return

	var left := 34.0
	var col := 640.0 / float(n)
	var name_sizes := [0, 0, 34, 28, 24]
	var mults := [0.0, 0.0, 0.78, 0.64, 0.58]
	var font_size: int = name_sizes[clampi(n, 0, name_sizes.size() - 1)]
	var mult: float = mults[clampi(n, 0, mults.size() - 1)]
	for i in n:
		var p = _players[i]
		var cx := left + (i + 0.5) * col
		var plat_w := col - 22.0
		_make_platform(root, Vector2(cx - plat_w * 0.5, 556.0), Vector2(plat_w, 104))
		var profile: Dictionary = Skulls.get_profile(str(p.get("skull_id")))
		_make_label(root, str(profile.get("name", profile.get("label", "无名者"))),
			Vector2(cx - col * 0.5, 52), Vector2(col, 60), font_size, HORIZONTAL_ALIGNMENT_CENTER)
		_make_preview(root, load(str(profile["data"])), float(profile.get("scale", 0.394)) * 1.35 * mult,
			Vector2(cx, 590), str((profile.get("anim", {}) as Dictionary).get("idle", "stand")), true, false)


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
	for p in _players:
		if is_instance_valid(p):
			p.show()
			p.set_physics_process(true)
	if is_instance_valid(_boss):
		_boss.show()
		_boss.set_physics_process(true)
		_boss.call("finish_entrance")
	finished.emit()
	queue_free()
