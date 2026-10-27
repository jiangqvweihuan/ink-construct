extends Node

## UI 冒烟测试：主菜单 -> 打开设置面板 -> 截图 -> 退出

const OUT_DIR := "res://tests/out/"

var _log: FileAccess

func p(msg) -> void:
	print("[UI] ", msg)
	if _log:
		_log.store_line("[UI] " + str(msg))
		_log.flush()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/ui_test.log", FileAccess.WRITE)

	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(0.6).timeout
	await _shot("01_main_menu")

	menu._open_settings()
	await get_tree().create_timer(0.4).timeout
	await _shot("02_settings")

	p("ALL DONE")
	get_tree().quit()

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + "ui_" + tag + ".png")
	p("saved " + tag + " err=" + str(err))
