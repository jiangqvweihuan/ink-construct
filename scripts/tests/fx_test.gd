extends Node2D

## 特效总览测试：深色底上把 12 条精灵条全放一遍，分三次截图人工检查效果。
## 每个特效旁边标名字，底部锚定的贴下排地面线，中心锚定的放上排。

const FX := preload("res://scripts/systems/fx.gd")
const OUT_DIR := "res://tests/out/"

var _log: FileAccess


func p(msg) -> void:
	print("[X] ", msg)
	if _log:
		_log.store_line("[X] " + str(msg))
		_log.flush()


func _ready() -> void:
	_log = FileAccess.open("res://tests/fx_test.log", FileAccess.WRITE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# 深灰底：特效里大量白/亮色，深底才能看清轮廓（接近实战的暗场景）
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.17, 0.19)
	bg.size = Vector2(1920, 720)
	add_child(bg)
	# 上排中心锚 / 下排底部锚，各 6 个
	var top := ["ink_hit", "ink_claw", "slash", "thunder", "speedline", "fire_hit"]
	var bot := ["pillar", "tiger", "fire_pillar", "crack", "gather", "vanish"]
	for i in top.size():
		var n: String = top[i]
		FX.spawn(self, n, Vector2(170.0 + i * 310.0, 230.0), {"scale": 0.7})
		_label(n, Vector2(170.0 + i * 310.0, 60.0))
	for i in bot.size():
		var n2: String = bot[i]
		FX.spawn(self, n2, Vector2(170.0 + i * 310.0, 660.0), {"scale": 0.7})
		_label(n2, Vector2(170.0 + i * 310.0, 420.0))
	p("spawned all")
	_run()


func _label(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	add_child(l)


func _run() -> void:
	await get_tree().create_timer(0.4).timeout
	await _shot("fx_a")
	# 上排短特效已播完，补一轮看中段
	for i in 6:
		FX.spawn(self, ["ink_hit", "ink_claw", "slash", "thunder", "speedline", "fire_hit"][i], Vector2(170.0 + i * 310.0, 230.0), {"scale": 0.7})
	await get_tree().create_timer(0.25).timeout
	await _shot("fx_b")
	await get_tree().create_timer(0.9).timeout
	await _shot("fx_c")
	p("ALL DONE")
	get_tree().quit()


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + tag + ".png")
	p("saved " + tag + " err=" + str(err))
