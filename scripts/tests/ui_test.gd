extends Node

## UI 冒烟测试：主菜单 -> 设置面板 -> 化身谱（含购买后重建）-> 图鉴（收录 / 点击演示 / 变式轮播 / 切页）
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

	# 化身谱：固定一份临时新档，覆盖滚动总览、买断、单角色修炼页与独立商栈。
	Meta.persist = false
	Meta.ink = 1000
	Meta.kills = 0
	Meta.clears = 0
	Meta.purchases = {}
	Meta.form_nodes = {}
	Meta.inventory = {}
	Meta.selected_supply = ""
	_menu._open_forms()
	await get_tree().create_timer(0.4).timeout
	var forms = _find_panel("forms_panel.gd")
	p("化身谱打开=%s（期望 true）" % (forms != null))
	await _shot("03_codex")
	if forms != null:
		forms._form_id = "c013"
		forms._refresh()
		await get_tree().create_timer(0.2).timeout
		await _shot("04_form_detail_locked")
		forms._buyout() # 修炼页顶部买断：解锁区仍保留在分支上方
		await get_tree().create_timer(0.2).timeout
		p("力僧买断=%s（期望 true）" % Meta.is_unlocked("c013"))
		Meta.learn_node("c013_guard_1")
		forms._refresh()
		await get_tree().create_timer(0.2).timeout
		await _shot("04b_form_detail_nodes")
		p("修炼节点已购=%s 可退=%s（期望 true / true）" % [Meta.has_form_node("c013_guard_1"), Meta.can_refund("c013_guard_1")])
		forms._back()
		await get_tree().create_timer(0.2).timeout
		forms._refresh() # 购买后走的重建路径
		await get_tree().create_timer(0.2).timeout
		await _shot("04c_codex_refresh")
		await _click(Vector2(135, 80)) # 「返回」在窗口左上角
		p("重建后点返回 -> 面板=%s（期望 false）" % (_find_panel("forms_panel.gd") != null))

	# 独立墨锭商栈：四个页签、补给库存与外观空分类都要能正常重建。
	_menu._open_shop()
	await get_tree().create_timer(0.3).timeout
	var shop = _find_panel("shop_panel.gd")
	p("墨锭商栈打开=%s（期望 true）" % (shop != null))
	if shop != null:
		await _shot("04d_shop_permanent")
		shop._set_tab("supply")
		Meta.buy("supply_revive")
		shop._refresh()
		await get_tree().create_timer(0.2).timeout
		await _shot("04e_shop_supply")
		p("复活墨符库存=%d（期望 1）" % Meta.supply_count("supply_revive"))
		shop._set_tab("reroll")
		await get_tree().process_frame
		await _shot("04f_shop_reroll")
		shop._set_tab("appearance")
		await get_tree().process_frame
		await _shot("04g_shop_appearance")
		shop._close()
		await get_tree().process_frame
		await get_tree().process_frame

	# 图鉴：先给存档造几条"已击败"记录（persist 关掉，不写进玩家存档），再看两页
	Meta.add_enemy_kill("c016")
	Meta.add_enemy_kill("c009")
	Meta.add_enemy_kill("c032")
	_menu._open_codex()
	await get_tree().create_timer(0.5).timeout
	var codex = _find_panel("codex_panel.gd")
	p("图鉴打开=%s（期望 true）" % (codex != null))
	await _shot("05_codex_enemy")

	if codex != null:
		# 敌人页：默认播待机；点击「招式 1」后演示台切到该招式，右侧简介要挂击败次数与词条
		var before := str(codex._current_anim)
		codex._pick(0)
		await get_tree().create_timer(0.25).timeout
		p("点击招式 1 -> 演示动画 %s（点击前 %s，期望不同）" % [str(codex._current_anim), before])
		var em: Dictionary = codex._model(codex._sel)
		p("简介含击败次数=%s 词条数=%d（期望 true / >0）" % [
			str(str(em["stat"]).contains("已击败")), (em["tags"] as Array).size()])
		await _shot("06_codex_pick")
		# 已收录的 Boss 详情（c032 三段变身）
		codex._select("c032")
		await get_tree().create_timer(0.3).timeout
		await _shot("07_codex_boss")
		# 化身页：切页后默认选中双刺
		codex._switch_tab(1)
		await get_tree().create_timer(0.3).timeout
		p("切到化身页 -> 选中=%s（期望 c021）" % str(codex._sel))
		await _shot("08_codex_form")
		# 银夜变式池：普攻 2 与 K 各留 2 条，I 只留 1 条；上 / 下键手动选择且不自动跳转
		Meta.clears = 3
		Meta.kills = 150
		codex._select("z003")
		await get_tree().create_timer(0.3).timeout
		var atk2 := -1
		var k := -1
		var i_skill := -1
		for i in codex._acts.size():
			var label := str(codex._acts[i]["label"])
			if label == "普攻 2":
				atk2 = i
			elif label == "技能 K":
				k = i
			elif label == "技能 I":
				i_skill = i
		var last_act: Dictionary = codex._acts[codex._acts.size() - 1] if codex._acts.size() > 0 else {}
		p("银夜变式数：普攻2=%d K=%d I=%d 被动末位=%s（期望 2 / 2 / 1 / true）" % [
			(codex._acts[atk2]["anims"] as Array).size() if atk2 >= 0 else 0,
			(codex._acts[k]["anims"] as Array).size() if k >= 0 else 0,
			(codex._acts[i_skill]["anims"] as Array).size() if i_skill >= 0 else 0,
			str(str(last_act.get("kind", "")) == "passive")])
		if k >= 0:
			codex._pick(k)
			await get_tree().create_timer(0.25).timeout
			var first_anim := str(codex._current_anim)
			await _press_key(KEY_DOWN)
			var second_anim := str(codex._current_anim)
			p("下键切换 %s -> %s（期望变化）" % [first_anim, second_anim])
			await get_tree().create_timer(1.0).timeout
			p("变式不自动跳转=%s（期望 true）" % str(str(codex._current_anim) == second_anim))
			await _press_key(KEY_UP)
			p("上键切回 -> %s（期望 %s）" % [str(codex._current_anim), first_anim])
			p("解析面板含切换提示=%s（期望 true）" % str(codex._desc_rt.text.contains("↑ / ↓ 切换")))
			await _press_key(KEY_DOWN)
		await _shot("09_codex_pool")
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
