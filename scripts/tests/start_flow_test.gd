extends Node2D

## 临时验证脚本：用真实鼠标事件点一遍主菜单 → 开始面板的所有按钮。
## 目的：pressed.emit() 不走 BaseButton 的输入路径，之前模拟测试漏掉了真实鼠标点击的崩溃。

const MENU := preload("res://scenes/ui/main_menu.tscn")
const OUT := "res://tests/start_flow.log"

var _log: FileAccess
var _menu: Node


func p(msg) -> void:
	print("[SF] ", msg)
	if _log:
		_log.store_line("[SF] " + str(msg))
		_log.flush()


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	_log = FileAccess.open(OUT, FileAccess.WRITE)
	_menu = MENU.instantiate()
	_menu.size = Vector2(1280, 720) # 挂在 Node2D 下时根 Control 不会自动铺满视口，背景/视频会变成 0 面积
	add_child(_menu)
	await get_tree().process_frame
	p("viewport=%s window=%s" % [get_viewport().get_visible_rect().size, get_window().size])
	await _shot("run_00_menu")

	await _click(Vector2(200, 624)) # 开始游戏
	p("点开始游戏 -> 面板=%s step=%d（期望 true / 0）" % [_panel() != null, _step(_panel())])
	await _shot("run_01_mode")

	await _click(Vector2(840, 365)) # 无尽
	p("点「无尽」-> step=%d（期望 1）" % _step(_panel()))
	await _shot("run_02_char")

	await _click(Vector2(640, 616)) # 上一步
	p("点「上一步」-> 面板=%s step=%d（期望 true / 0）" % [_panel() != null, _step(_panel())])
	await _shot("run_03_back")

	await _click(Vector2(440, 365)) # 冒险
	p("点「冒险」-> step=%d（期望 1）" % _step(_panel()))
	await _shot("run_04_char2")

	await _click(Vector2(640, 616)) # 上一步
	p("再点「上一步」-> step=%d（期望 0）" % _step(_panel()))

	await _click(Vector2(640, 616)) # 返回
	p("点「返回」-> 面板=%s（期望 false）" % (_panel() != null))
	await _shot("run_05_closed")

	await _click(Vector2(200, 624)) # 再开一次
	p("二次点开始游戏 -> 面板=%s step=%d（期望 true / 0）" % [_panel() != null, _step(_panel())])
	await _click(Vector2(840, 365)) # 无尽
	p("二次点「无尽」-> step=%d（期望 1）" % _step(_panel()))
	await _shot("run_06_reopen")

	await _esc()
	p("Esc（选角页）-> 面板=%s step=%d（期望 true / 0）" % [_panel() != null, _step(_panel())])
	await _esc()
	p("再按 Esc -> 面板=%s（期望 false）" % (_panel() != null))

	await _click(Vector2(200, 624)) # 开始游戏
	await _click(Vector2(200, 624)) # 连点
	p("连点两次开始游戏 -> 面板数=%d（期望 1）" % _panel_count())
	await _shot("run_07_double")

	p("=== 全部点击跑完，无崩溃 ===")
	await get_tree().create_timer(8.0).timeout # 留点时间给外部抓日志
	get_tree().quit()


func _panel() -> Node:
	for c in _menu.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("start_panel.gd"):
			return c
	return null


func _step(panel: Node) -> int:
	return int(panel.get("_step")) if panel != null else -1


func _panel_count() -> int:
	var n := 0
	for c in _menu.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("start_panel.gd"):
			n += 1
	return n


func _esc() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	get_viewport().push_input(ev)
	await get_tree().process_frame
	await get_tree().process_frame


func _click(pos: Vector2) -> void:
	# in_local_coords = true：直接给 1280x720 设计坐标，交给视口自己换算拉伸
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


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png("res://tests/out/" + shot_name + ".png")
	p("saved " + shot_name + " err=" + str(err))
