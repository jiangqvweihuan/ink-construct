extends Node2D

## 开始流程真实鼠标回归：择路 → 问境 → 化身 → 启程，并断言五档数量/攻击数值。

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
	_menu.size = Vector2(1280, 720)
	add_child(_menu)
	await get_tree().process_frame
	await _shot("run_00_menu")

	await _click(Vector2(110, 624))
	p("点开始游戏 -> 面板=%s step=%d（期望 true / 0）" % [_panel() != null, _step(_panel())])
	await _shot("run_01_mode")

	await _click(Vector2(840, 365)) # 无尽
	p("点「无尽」-> step=%d（期望 1）" % _step(_panel()))
	await _shot("run_02_difficulty_endless")

	await _click(Vector2(1060, 365)) # 无归
	p("点「无归」-> step=%d difficulty=%d（期望 2 / 4）" % [_step(_panel()), _difficulty(_panel())])
	await _click(Vector2(150, 360)) # 选中双刺，不直接开局
	p("点角色卡 -> step=%d char=%s scene=%s（选中但不启程）" % [_step(_panel()), str(_panel().get("_char")), get_tree().current_scene.name])
	await _shot("run_03_character_preview")

	await _click(Vector2(210, 616))
	p("化身页上一步 -> step=%d（期望 1）" % _step(_panel()))
	await _click(Vector2(420, 365)) # 落笔
	p("点「落笔」-> step=%d difficulty=%d（期望 2 / 1）" % [_step(_panel()), _difficulty(_panel())])
	await _click(Vector2(210, 616))
	await _click(Vector2(210, 610))
	p("连续上一步 -> step=%d（期望 0）" % _step(_panel()))
	await _click(Vector2(640, 610))
	p("点「返回」-> 面板=%s（期望 false）" % (_panel() != null))

	await _click(Vector2(110, 624))
	await _click(Vector2(440, 365)) # 冒险
	await _click(Vector2(850, 365)) # 狂澜
	p("冒险狂澜 -> step=%d difficulty=%d（期望 2 / 3）" % [_step(_panel()), _difficulty(_panel())])
	await _shot("run_04_character_adventure")
	var scroll: ScrollContainer = null
	for child in _panel().get_children():
		if child is ScrollContainer:
			scroll = child
			break
	if scroll != null:
		var bar := scroll.get_h_scroll_bar()
		p("选角滚动条：内容上限=%.1f 可视页=%.1f 可见=%s（期望上限大于可视页且可见）" % [bar.max_value, bar.page, bar.is_visible_in_tree()])
		var rect := bar.get_global_rect()
		await _drag(rect.position + Vector2(rect.size.x * 0.4, rect.size.y * 0.5), rect.end - Vector2(8, rect.size.y * 0.5))
		p("拖动选角滚动条 -> offset=%d（期望 > 0）" % scroll.scroll_horizontal)
		await _shot("run_04b_character_scrolled")
	await _esc()
	p("Esc 化身 -> step=%d（期望 1）" % _step(_panel()))
	await _esc()
	p("Esc 问境 -> step=%d（期望 0）" % _step(_panel()))
	await _esc()
	p("Esc 择路 -> 面板=%s（期望 false）" % (_panel() != null))

	await _click(Vector2(110, 624))
	await _click(Vector2(110, 624))
	p("连点两次开始游戏 -> 面板数=%d（期望 1）" % _panel_count())

	Run.start(Run.MODE_ADVENTURE, "c021", 0)
	p("濡墨首波=%d（期望 4）" % int(Run.room_config()["waves"][0]["count"]))
	Run.start(Run.MODE_ADVENTURE, "c021", 4)
	p("无归首波=%d（期望 9）" % int(Run.room_config()["waves"][0]["count"]))
	Run.room_index = 1
	p("无归中庭首波=%d（期望 10 = 普通 9 + 精英 1）" % int(Run.room_config()["waves"][0]["count"]))
	Run.start(Run.MODE_ENDLESS, "c021", 4)
	p("无尽无归初始首波=%d（期望 7）" % int(Run.room_config()["waves"][0]["count"]))
	Run.room_index = Run.ROOMS.size()
	p("无尽首层 Boss 房已清房间=%d（期望 3）" % Run.cleared_room_count())
	Run.advance()
	p("无尽进入第二层：depth=%d room=%d 已清房间=%d（期望 2 / 0 / 4）" % [Run.depth, Run.room_index, Run.cleared_room_count()])
	Run.room_index = 2
	p("无尽第二层清两房后已清房间=%d（期望 6）" % Run.cleared_room_count())
	for i in Run.DIFFICULTIES.size():
		Run.difficulty = i
		p("%s：基础 2 攻 -> %d" % [Run.difficulty_label(), Run.enemy_damage(2)])
	Run.start()
	p("无参开局难度=%d（期望默认落笔 1）" % Run.difficulty)

	# 最终真实点一次「启程」，确认只有按钮会开局，且模式/难度/角色正确带入。
	await _click(Vector2(440, 365))
	await _click(Vector2(635, 365)) # 惊锋
	await _click(Vector2(150, 360))
	p("即将启程：mode=%s difficulty=%d skull=%s（期望 adventure / 2 / c021）" % [_mode(_panel()), _difficulty(_panel()), str(_panel().get("_char"))])
	# 点击后当前测试场景会被房间替换；由 SceneTree 自身持有退出计时器。
	get_tree().create_timer(1.5).timeout.connect(get_tree().quit)
	await _click(Vector2(1040, 616), true)


func _panel() -> Node:
	if not is_instance_valid(_menu):
		return null
	for c in _menu.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("start_panel.gd"):
			return c
	return null


func _step(panel: Node) -> int:
	return int(panel.get("_step")) if panel != null else -1


func _difficulty(panel: Node) -> int:
	return int(panel.get("_difficulty")) if panel != null else -1


func _mode(panel: Node) -> String:
	return str(panel.get("_mode")) if panel != null else ""


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


func _click(pos: Vector2, final := false) -> void:
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
	if final:
		return
	await get_tree().process_frame
	await get_tree().process_frame


func _drag(from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	get_viewport().push_input(down, true)
	await get_tree().process_frame
	for i in range(1, 9):
		var move := InputEventMouseMotion.new()
		move.position = from.lerp(to, float(i) / 8.0)
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(move, true)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	get_viewport().push_input(up, true)
	await get_tree().process_frame
	await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	var err = img.save_png("res://tests/out/" + shot_name + ".png")
	p("saved " + shot_name + " err=" + str(err))
