extends Node

## UI 冒烟测试：主菜单 -> 设置面板 -> 化身谱（含购买后重建）-> 图鉴（收录 / 悬停演示 / 切页）
## -> 截图 -> 退出。化身谱部分用真实鼠标点「返回」：_refresh 重建后点击音节点必须还在。

const OUT_DIR := "res://tests/out/"

const Settings = preload("res://scripts/ui/settings.gd") # 改键回归用

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

	# 致谢：左侧竖排入口 → 滚动名单（打开后必须真的在上移）
	_menu._open_credits()
	await get_tree().create_timer(0.5).timeout
	var credits = _find_panel("credits_panel.gd")
	p("致谢打开=%s（期望 true）" % (credits != null))
	if credits != null:
		p("致谢滚动 offset=%.1f（期望 > 0）" % credits._offset)
		await _shot("01b_credits")
		# 致谢期间点主菜单区域不能穿透（全屏遮罩必须吃掉点击）
		await _click(Vector2(200, 624))
		p("致谢中点击菜单区 -> 开始面板=%s（期望 false）" % (_find_panel("start_panel.gd") != null))
		credits.queue_free()
		await get_tree().process_frame

	# 设置：三页签截图 + 改键/冲突/Esc 取消（persist 关掉，不写玩家配置）
	Settings.persist = false
	_menu._open_settings()
	await get_tree().create_timer(0.4).timeout
	var sp = _find_panel("settings_panel.gd")
	p("设置打开=%s（期望 true）" % (sp != null))
	await _shot("02_settings_audio")
	if sp != null:
		sp._switch_tab("画面")
		await get_tree().process_frame
		await _shot("02b_settings_video")
		sp._switch_tab("操作")
		await get_tree().process_frame
		await _shot("02c_settings_keys")
		# 改键：跳跃 Space -> G，InputMap 与按钮文字都要跟着变
		sp._start_capture("jump")
		await _press_key(KEY_G)
		p("改键 jump -> %s 按钮=%s（期望 G / G）" % [Settings.action_label("jump"), sp._key_btns["jump"].text])
		# 冲突：闪避想绑 G（已被跳跃占用）-> 拒绝并出提示
		sp._start_capture("dash")
		await _press_key(KEY_G)
		p("冲突绑定被拒 dash 仍=%s hint=%s（期望 Sh / 非空）" % [Settings.action_label("dash"), sp._hint.text])
		# Esc 取消录入
		sp._start_capture("dash")
		await _press_key(KEY_ESCAPE)
		p("Esc 取消录入 dash 仍=%s（期望 Sh）" % Settings.action_label("dash"))
	await get_tree().create_timer(0.2).timeout
	_close_settings() # 先关掉设置，别让它的窗口叠在化身谱截图里
	await get_tree().process_frame

	# 化身谱：先看初始排版，再模拟一次"买完刷新"后点返回（重建后按钮必须还能点）
	_menu._open_forms()
	await get_tree().create_timer(0.4).timeout
	var forms = _find_panel("forms_panel.gd")
	p("化身谱打开=%s（期望 true）" % (forms != null))
	await _shot("03_codex")
	if forms != null:
		forms._refresh() # 购买后走的重建路径
		await get_tree().create_timer(0.2).timeout
		await _shot("04_codex_refresh")
		await _click(Vector2(135, 80)) # 「返回」在窗口左上角
		p("重建后点返回 -> 面板=%s（期望 false）" % (_find_panel("forms_panel.gd") != null))

	# 图鉴：先给存档造几条"已击败"记录（persist 关掉，不写进玩家存档），再看两页
	Meta.persist = false
	Meta.add_enemy_kill("c016")
	Meta.add_enemy_kill("c009")
	Meta.add_enemy_kill("c032")
	_menu._open_codex()
	await get_tree().create_timer(0.5).timeout
	var codex = _find_panel("codex_panel.gd")
	p("图鉴打开=%s（期望 true）" % (codex != null))
	await _shot("05_codex_enemy")

	if codex != null:
		# 敌人页：鼠标停在第一条「招式 1」上，预览要切到该招式动画
		var before := str(codex._current_anim)
		await _hover(Vector2(560, 470))
		await get_tree().create_timer(0.2).timeout
		p("悬停招式 -> 预览动画 %s（悬停前 %s，期望不同）" % [str(codex._current_anim), before])
		await _shot("06_codex_hover")
		# 已收录的 Boss 详情（c032 三段变身）
		codex._select("c032")
		await get_tree().create_timer(0.3).timeout
		await _shot("07_codex_boss")
		# 化身页：切页后默认选中双刺，再悬停一个技能
		codex._switch_tab(1)
		await get_tree().create_timer(0.3).timeout
		p("切到化身页 -> 选中=%s（期望 c021）" % str(codex._sel))
		await _hover(Vector2(560, 470))
		await get_tree().create_timer(0.2).timeout
		p("化身页悬停 -> 预览动画=%s" % str(codex._current_anim))
		await _shot("08_codex_form")
		await _click(Vector2(135, 594)) # 「返回」在左栏下方
		await get_tree().process_frame
		p("图鉴点返回 -> 面板=%s（期望 false）" % (_find_panel("codex_panel.gd") != null))

	p("ALL DONE")
	get_tree().quit()


func _find_panel(script_name: String) -> Node:
	for c in _menu.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with(script_name):
			return c
	return null


func _close_settings() -> void:
	for c in _menu.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("settings_panel.gd"):
			c.queue_free()


## 真实按键（改键录入走 _input 路径）
func _press_key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	get_viewport().push_input(ev)
	await get_tree().process_frame


## 真实鼠标移动（触发 mouse_entered，图鉴的悬停演示靠它）
func _hover(pos: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = pos
	get_viewport().push_input(move, true)
	await get_tree().process_frame


## 真实鼠标点击（in_local_coords：直接用 1280x720 设计坐标）
func _click(pos: Vector2) -> void:
	await _hover(pos)

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
