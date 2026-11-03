extends Node

## 字体探针：同文字、字号与缩放下对照两款字体的 MSDF / 普通灰度渲染。

const OUT_DIR := "res://tests/out/"
const SAMPLE := "残卷 墨构 武车 红蝶 设置 殁于 命火自熄"
const PAPER := Color(0.92, 0.89, 0.79)
const DIM := Color(0.62, 0.60, 0.54)

var _log: FileAccess


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/font_probe.log", FileAccess.WRITE)
	var theme: Theme = load(str(ProjectSettings.get_setting("gui/theme/custom")))
	_log.store_line("setting = " + str(ProjectSettings.get_setting("gui/theme/custom")))
	_log.store_line("default_font = " + str(theme.default_font if theme != null else null))

	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.06, 0.055)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var body: FontFile = load("res://art/ui/fonts/pangmen.ttf")
	var title: FontFile = load("res://art/ui/fonts/slidefu_regular.ttf")
	var layer := Control.new()
	add_child(layer)
	_compare_font("庞门正文", body, layer)
	await _shot("font_compare_body")
	layer.queue_free()
	await get_tree().process_frame
	layer = Control.new()
	add_child(layer)
	_compare_font("庞门正文", body, layer, true)
	await _shot("font_compare_body_48")
	layer.queue_free()
	await get_tree().process_frame
	layer = Control.new()
	add_child(layer)
	_compare_font("佛系标题", title, layer)
	await _shot("font_compare_title")
	_log.flush()
	_log.close()
	get_tree().quit()


func _compare_font(title: String, source: FontFile, layer: Control, tuned_msdf := false) -> void:
	var comparison := source.duplicate() as FontFile
	comparison.multichannel_signed_distance_field = tuned_msdf
	if tuned_msdf:
		comparison.msdf_size = 48
		comparison.msdf_pixel_range = 8
	comparison.clear_cache()
	_log.store_line("%s source_msdf=%s comparison_msdf=%s source_size=%d source_range=%d comparison_size=%d comparison_range=%d" % [
		title, source.multichannel_signed_distance_field, comparison.multichannel_signed_distance_field,
		source.msdf_size, source.msdf_pixel_range, comparison.msdf_size, comparison.msdf_pixel_range,
	])
	_text(title, Vector2(20, 8), 20, DIM, source, 0, layer)
	_text("当前 MSDF", Vector2(20, 42), 18, DIM, source, 0, layer)
	_text("MSDF 48 / 8" if tuned_msdf else "关闭 MSDF", Vector2(650, 42), 18, DIM, comparison, 0, layer)
	var sizes := [14, 18, 24, 48, 72, 110]
	var y := 76.0
	for font_size in sizes:
		var sample: String = SAMPLE if font_size <= 24 else ("残卷 墨构 武车 红蝶" if font_size <= 72 else "残卷")
		_text("%d  %s" % [font_size, sample], Vector2(20, y), font_size, PAPER, source, 0, layer)
		_text("%d  %s" % [font_size, sample], Vector2(650, y), font_size, PAPER, comparison, 0, layer)
		y += font_size + 18.0
	_text("描边对照  残卷山谷 · 墨堂深处", Vector2(20, 646), 24, PAPER, source, 4, layer)
	_text("描边对照  残卷山谷 · 墨堂深处", Vector2(650, 646), 24, PAPER, comparison, 4, layer)


func _text(text: String, pos: Vector2, font_size: int, color: Color, font: FontFile, outline: int, layer: Control) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.02))
	label.add_theme_constant_override("outline_size", outline)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + tag + ".png")
	_log.store_line("saved " + tag + " err=" + str(err))
