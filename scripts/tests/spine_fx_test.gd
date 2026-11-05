extends Node2D

## 新 Spine 特效资源总览：验证 35 组骨架、动画与尺寸，并输出同屏截图。
const SpineFX := preload("res://scripts/systems/spine_fx.gd")
const OUT_DIR := "res://tests/out/"
const IDS := [
	"E54156", "E54151", "E54148", "E54110", "E54083", "E54063", "E54061",
	"E54056", "E54055", "E54054", "E54015", "E54012", "E53201", "E53174",
	"E53038", "E53026", "E53009", "E53008", "E52025", "E52007", "E52000",
	"E50127", "E50041", "E100186", "E100182", "E100180", "E100177", "E100172",
	"E100129", "E54068", "E100006", "E21105", "E21022", "E21019", "E21013",
	"E54169", "E100105", "E54145", "E54181", "E54057",
]
const EXPECTED_ANIMS := {
	"E54110": ["action1"],
	"E54083": ["action1", "action2", "action3"],
	"E54012": ["action1", "action3"],
	"E54068": ["action1", "action2"],
	"E21013": ["win", "lose"],
}
const THUMB_SCALE := {
	"E54156": 0.65, "E54151": 0.12, "E54148": 0.65, "E54110": 0.45,
	"E54083": 0.16, "E54063": 0.12, "E54061": 0.014, "E54056": 0.14,
	"E54055": 0.14, "E54054": 0.18, "E54015": 0.22, "E54012": 0.12,
	"E53201": 0.22, "E53174": 0.16, "E53038": 0.14, "E53026": 0.17,
	"E53009": 0.35, "E53008": 0.4, "E52025": 0.14, "E52007": 0.8,
	"E52000": 1.0, "E50127": 0.18, "E50041": 0.55, "E100186": 0.55,
	"E100182": 0.55, "E100180": 1.2, "E100177": 0.4, "E100172": 0.5,
	"E100129": 0.1, "E54068": 0.2, "E100006": 0.15, "E21105": 0.1,
	"E21022": 0.18, "E21019": 0.18, "E21013": 0.18,
	"E54169": 0.65, "E100105": 0.35, "E54145": 0.1, "E54181": 0.1, "E54057": 0.3,
}

var _log: FileAccess
var _failures := 0
var _nodes: Dictionary = {}


func p(msg: Variant) -> void:
	print("[SFX] ", msg)
	if _log != null:
		_log.store_line("[SFX] " + str(msg))
		_log.flush()


func check(ok: bool, label: String) -> void:
	p(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_failures += 1


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/spine_fx_test.log", FileAccess.WRITE)
	for cls in ["SpineSkeleton", "SpineAtlasResource"]:
		var methods: Array[String] = []
		for method in ClassDB.class_get_method_list(cls, true):
			methods.append(str(method["name"]))
		p("methods %s: %s" % [cls, ", ".join(methods)])
	get_window().size = Vector2i(1400, 1000)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.15)
	bg.size = Vector2(1400, 1000)
	bg.z_index = -100
	add_child(bg)
	for i in IDS.size():
		var id: String = IDS[i]
		var d = SpineFX.data(id)
		check(d != null, id + " skeleton loads")
		if d == null:
			continue
		var names := SpineFX.animation_names(id)
		check(not names.is_empty(), id + " has animations")
		var durations: Array = []
		for anim_name in names:
			var a = d.call("find_animation", anim_name)
			durations.append(float(a.call("get_duration")) if a != null else -1.0)
		p("%s anims=%s durations=%s bounds=(%s,%s,%s,%s)" % [id, names, durations,
			d.call("get_x"), d.call("get_y"), d.call("get_width"), d.call("get_height")])
		for expected in EXPECTED_ANIMS.get(id, []):
			check(names.has(expected), "%s includes %s" % [id, expected])
		var pos := Vector2(100 + (i % 7) * 200, 128 + (i / 7) * 150)
		var fx := SpineFX.spawn(self, id, pos, {"scale": float(THUMB_SCALE[id]), "loop": true, "auto_free": false})
		check(fx != null, id + " spawns")
		_nodes[id] = fx
		_label(id, pos + Vector2(-58, 58))
		_label("/".join(names), pos + Vector2(-82, 76), 11)
	await get_tree().create_timer(0.55).timeout
	for id in IDS:
		var fx: Node2D = _nodes[id]
		var bounds = fx.sprite.call("get_skeleton").call("get_bounds")
		p("%s runtime_bounds=%s type=%s" % [id, bounds, typeof(bounds)])
	var fit_height := SpineFX.spawn(self, "E21013", Vector2(-500, -500),
		{"anim": "win", "height": 200.0, "loop": true, "auto_free": false})
	var height_bounds: Rect2 = await _wait_for_bounds(fit_height)
	p("fit_height settled bounds=%s scale=%s offset=%s" % [height_bounds, fit_height.sprite.scale, fit_height.sprite.position])
	check(absf(height_bounds.size.y * fit_height.sprite.scale.y - 200.0) < 0.5,
		"runtime height fitting works when static bounds are zero")
	fit_height.call("play", "lose", true, 1.0, false)
	height_bounds = await _wait_for_bounds(fit_height)
	check(absf(height_bounds.size.y * fit_height.sprite.scale.y - 200.0) < 0.5,
		"runtime height fitting refreshes after animation changes")
	fit_height.queue_free()
	var fit_width := SpineFX.spawn(self, "E21022", Vector2(-500, -500),
		{"width": 470.0, "center": true, "loop": true, "auto_free": false})
	var width_bounds: Rect2 = await _wait_for_bounds(fit_width)
	p("fit_width settled bounds=%s scale=%s offset=%s" % [width_bounds, fit_width.sprite.scale, fit_width.sprite.position])
	check(absf(width_bounds.size.x * fit_width.sprite.scale.x - 470.0) < 0.5,
		"runtime width fitting uses the active animation bounds")
	var visual_center: Vector2 = width_bounds.get_center() * fit_width.sprite.scale + fit_width.sprite.position
	check(visual_center.length() < 0.01, "center option aligns the runtime visual bounds to the requested position")
	fit_width.queue_free()
	var cover_size := Vector2(1280, 720)
	var fit_cover := SpineFX.spawn(self, "E21022", Vector2(-500, -500),
		{"cover": cover_size, "center": true, "loop": true, "auto_free": false})
	var cover_bounds: Rect2 = await _wait_for_bounds(fit_cover)
	var covered: Vector2 = cover_bounds.size * fit_cover.sprite.scale
	check(covered.x >= cover_size.x - 0.5 and covered.y >= cover_size.y - 0.5 \
		and absf(minf(covered.x - cover_size.x, covered.y - cover_size.y)) < 0.5,
		"runtime cover fitting fills the target without distorting the animation")
	visual_center = cover_bounds.get_center() * fit_cover.sprite.scale + fit_cover.sprite.position
	check(visual_center.length() < 0.01, "cover fitting keeps the full-screen effect centered")
	fit_cover.queue_free()
	await _shot("spine_fx_grid_a")
	await get_tree().create_timer(0.85).timeout
	await _shot("spine_fx_grid_b")
	for id in EXPECTED_ANIMS:
		for anim_name in EXPECTED_ANIMS[id]:
			var fx: Node2D = _nodes.get(id)
			if fx != null and is_instance_valid(fx):
				fx.call("play", anim_name, true, 1.0, false)
				await get_tree().create_timer(0.35).timeout
				await _shot("spine_fx_%s_%s" % [id, anim_name])
	check(_failures == 0, "resource and animation inventory")
	p("RESULT %d failures" % _failures)
	p("ALL DONE")
	get_tree().quit(0 if _failures == 0 else 1)


func _wait_for_bounds(fx: Node2D) -> Rect2:
	var bounds := Rect2()
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 2000:
		bounds = fx.sprite.call("get_skeleton").call("get_bounds")
		if fx.sprite.self_modulate.a > 0.99 and SpineFX._valid_bounds(bounds):
			return bounds
		await get_tree().process_frame
	p("bounds wait timed out after %dms scale=%s bounds=%s" % [Time.get_ticks_msec() - started, fx.sprite.scale, bounds])
	return bounds


func _label(text: String, pos: Vector2, font_size := 15) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_color_override("font_color", Color(0.92, 0.9, 0.84))
	label.add_theme_font_size_override("font_size", font_size)
	label.z_index = 100
	add_child(label)


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + tag + ".png")
	check(err == OK, "save " + tag)
