extends Node2D

## 开始流程真实鼠标回归：择途 → 择路 → 问境 → 化身 → 启程，并断言五档数量/攻击数值。

const MENU := preload("res://scenes/ui/main_menu.tscn")
const OUT := "res://tests/start_flow.log"
const SINGLE_CARD := Vector2(296, 422) # 择途层首卡中心（1280 宽三卡布局）

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
	p("点开始游戏 -> 择途层=%s（期望 true）" % (_mode_layer() != null))
	assert(_mode_layer() != null, "开始游戏必须先铺择途层")
	await _click(SINGLE_CARD)
	p("点单人 -> 面板=%s step=%d（期望 true / 0）" % [_panel() != null, _step(_panel())])
	var initial_panel := _panel()
	assert(initial_panel != null, "开始面板必须打开")
	initial_panel._start_run()
	assert(not initial_panel._starting, "模式/角色校验失败不得锁死后续启程")
	assert(initial_panel._sfx.bus == "SFX", "开始面板常驻点击音必须走 SFX 总线")
	await _shot("run_01_mode")

	await _click(Vector2(840, 365)) # 无尽
	p("点「无尽」-> step=%d（期望 1）" % _step(_panel()))
	await _shot("run_02_difficulty_endless")

	await _click(Vector2(1060, 365)) # 无归
	p("点「无归」-> step=%d difficulty=%d（期望 2 / 4）" % [_step(_panel()), _difficulty(_panel())])
	await _click(Vector2(150, 360)) # 选中绯刃，不直接开局
	p("点角色卡 -> step=%d char=%s scene=%s（选中但不启程）" % [_step(_panel()), str(_panel().get("_char")), get_tree().current_scene.name])
	var char_panel := _panel()
	p("绯刃选角原画=%s 完整容纳=%s（期望 true / true）" % [
		is_instance_valid(char_panel._portrait) and char_panel._portrait.texture != null,
		is_instance_valid(char_panel._portrait) and char_panel._portrait.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED])
	await _shot("run_03_character_preview")

	# 没有原画的镇岳仍显示原有 Spine 动作，不留空框；随后恢复绯刃继续旧流程。
	var purchases_before: Dictionary = Meta.purchases.duplicate()
	Meta.purchases["buyout_c013"] = true
	char_panel._pick_char("c013")
	await get_tree().process_frame
	await get_tree().process_frame
	var has_spine := false
	for child in char_panel.get_children():
		if child.get_class() == "SpineSprite":
			has_spine = true
	p("镇岳缺原画回退：原画为空=%s Spine动作=%s（期望 true / true）" % [char_panel._portrait == null, has_spine])
	await _shot("run_03b_character_spine_fallback")
	Meta.purchases = purchases_before
	char_panel._pick_char("c021")
	await get_tree().process_frame
	await get_tree().process_frame

	await _click(Vector2(210, 616))
	p("化身页上一步 -> step=%d（期望 1）" % _step(_panel()))
	await _click(Vector2(420, 365)) # 落笔
	p("点「落笔」-> step=%d difficulty=%d（期望 2 / 1）" % [_step(_panel()), _difficulty(_panel())])
	await _click(Vector2(210, 616))
	await _click(Vector2(210, 610))
	p("连续上一步 -> step=%d（期望 0）" % _step(_panel()))
	await _click(Vector2(640, 610))
	p("点「返回」-> 面板=%s（期望 false）" % (_panel() != null))
	await _esc()
	p("Esc 择途层 -> 层=%s（期望 false）" % (_mode_layer() != null))

	await _click(Vector2(110, 624))
	await _click(SINGLE_CARD)
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
	await _esc()
	p("Esc 择途层 -> 层=%s（期望 false）" % (_mode_layer() != null))

	await _click(Vector2(110, 624))
	await _click(Vector2(110, 624))
	p("连点两次开始游戏 -> 择途层数=%d（期望 1）" % _mode_count())
	assert(_mode_count() == 1, "连点开始游戏不得叠出多层择途")
	await _click(SINGLE_CARD)

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
	# 补给卡在面板构建时按库存决定能否点击，必须先塞库存再进化身步，
	# 否则本地存档补给为空时点击会被 disabled 吞掉。
	Meta.persist = false
	Meta.inventory["supply_revive"] = 2
	await _click(Vector2(440, 365))
	await _click(Vector2(635, 365)) # 惊锋
	await _click(Vector2(150, 360))
	p("即将启程：mode=%s difficulty=%d skull=%s（期望 adventure / 2 / c021）" % [_mode(_panel()), _difficulty(_panel()), str(_panel().get("_char"))])
	await _click(Vector2(507, 553)) # 复活墨符：真实选择两件同类补给，供重复启程回归使用。
	assert(_panel()._supply == "supply_revive", "启程前必须选中复活墨符")
	assert(_panel()._start_button != null, "必须持有实际启程按钮")
	# 点击后当前测试场景会被房间替换；由 SceneTree 自身持有退出计时器。
	get_tree().create_timer(1.5).timeout.connect(get_tree().quit)
	await _click(Vector2(1040, 616), true)


func _find(node: Node, script_name: String) -> Node:
	if node.get_script() != null and str(node.get_script().resource_path).ends_with(script_name):
		return node
	for c in node.get_children():
		var hit := _find(c, script_name)
		if hit != null:
			return hit
	return null


func _panel() -> Node:
	if not is_instance_valid(_menu):
		return null
	return _find(_menu, "start_panel.gd")


func _mode_layer() -> Node:
	if not is_instance_valid(_menu):
		return null
	return _find(_menu, "mode_select.gd")


func _step(panel: Node) -> int:
	return int(panel.get("_step")) if panel != null else -1


func _difficulty(panel: Node) -> int:
	return int(panel.get("_difficulty")) if panel != null else -1


func _mode(panel: Node) -> String:
	return str(panel.get("_mode")) if panel != null else ""


func _count(node: Node, script_name: String) -> int:
	var n := 1 if node.get_script() != null and str(node.get_script().resource_path).ends_with(script_name) else 0
	for c in node.get_children():
		n += _count(c, script_name)
	return n


func _panel_count() -> int:
	if not is_instance_valid(_menu):
		return 0
	return _count(_menu, "start_panel.gd")


func _mode_count() -> int:
	if not is_instance_valid(_menu):
		return 0
	return _count(_menu, "mode_select.gd")


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
	var root := get_tree().root
	var embark_stream: AudioStream = null
	if final:
		var current_panel := _panel()
		embark_stream = current_panel.SFX_RUN_EMBARK if current_panel != null else null
	get_viewport().push_input(up, true)
	if final:
		var panel := _panel()
		assert(panel != null, "真实点击启程后面板在切场景前应仍可检查")
		if panel == null:
			return
		assert(bool(panel.get("_starting")), "第一次有效启程必须置位防重标记")
		var start_button := panel.get("_start_button") as TextureButton
		assert(start_button != null and start_button.disabled, "第一次启程必须立即禁用实际按钮")
		assert(Meta.supply_count("supply_revive") == 1, "第一次启程必须只消耗一件补给")
		panel._start_run() # 切场景尚未提交时同步重复调用。
		assert(Meta.supply_count("supply_revive") == 1, "重复启程不得消耗第二件补给")
		assert(Run.supply_revive, "重复启程不得重置已带入的补给")
		var embark_sfx: AudioStreamPlayer = null
		for child in root.get_children():
			if child is AudioStreamPlayer and child.stream == embark_stream:
				embark_sfx = child
				break
		assert(embark_sfx != null, "启程音效应由 root 级播放器播放")
		if embark_sfx != null:
			assert(embark_sfx.bus == "SFX", "启程音效必须走 SFX 总线")
			assert(embark_sfx.get_parent() == root, "启程音效不得随开始面板销毁")
			assert(embark_sfx.finished.is_connected(embark_sfx.queue_free), "启程音效结束后必须自行释放")
		p("启程真实输入/直接重复调用、按钮禁用、单件消耗与 SFX 总线断言通过")
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
	# 无头下 frame_post_draw 不发射：改用 process_frame + force_draw，并以空图判断兜底。
	await get_tree().process_frame
	# 无头下没有可读帧，直接跳过截图，避免 dummy 纹理报错。
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw()
	var img = get_viewport().get_texture().get_image()
	if img == null:
		p("screenshot unavailable " + shot_name)
		return
	var err = img.save_png("res://tests/out/" + shot_name + ".png")
	p("saved " + shot_name + " err=" + str(err))
