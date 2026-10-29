extends Node

## UI 冒烟测试：主菜单 -> 设置面板 -> 化身谱（含购买后重建）-> 截图 -> 退出
## 化身谱部分用真实鼠标点「返回」：_refresh 重建后点击音节点必须还在，不能一按就报
## "Cannot call method 'play' on a previously freed instance"

const OUT_DIR := "res://tests/out/"

var _log: FileAccess
var _menu: Node

func p(msg) -> void:
	print("[UI] ", msg)
	if _log:
		_log.store_line("[UI] " + str(msg))
		_log.flush()

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/ui_test.log", FileAccess.WRITE)

	_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(_menu)
	await get_tree().create_timer(0.6).timeout
	await _shot("01_main_menu")

	_menu._open_settings()
	await get_tree().create_timer(0.4).timeout
	await _shot("02_settings")
	_close_settings() # 先关掉设置，别让它的窗口叠在化身谱截图里
	await get_tree().process_frame

	# 化身谱：先看初始排版，再模拟一次"买完刷新"后点返回（重建后按钮必须还能点）
	_menu._open_codex()
	await get_tree().create_timer(0.4).timeout
	var codex = _codex()
	p("化身谱打开=%s（期望 true）" % (codex != null))
	await _shot("03_codex")
	if codex != null:
		codex._refresh() # 购买后走的重建路径
		await get_tree().create_timer(0.2).timeout
		await _shot("04_codex_refresh")
		await _click(Vector2(135, 80)) # 「返回」在窗口左上角
		p("重建后点返回 -> 面板=%s（期望 false）" % (_codex() != null))

	p("ALL DONE")
	get_tree().quit()


func _codex() -> Node:
	for c in _menu.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("forms_panel.gd"):
			return c
	return null


func _close_settings() -> void:
	for c in _menu.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("settings_panel.gd"):
			c.queue_free()


## 真实鼠标点击（in_local_coords：直接用 1280x720 设计坐标）
func _click(pos: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = pos
	get_viewport().push_input(move, true)
	await get_tree().process_frame

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	get_viewport().push_input(down, true)
	await get_tree().process_frame

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	get_viewport().push_input(up, true)
	await get_tree().process_frame
	await get_tree().process_frame


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png(OUT_DIR + "ui_" + tag + ".png")
	p("saved " + tag + " err=" + str(err))
