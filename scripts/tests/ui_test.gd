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
	Meta.add_enemy_kill("c017")
	Meta.add_enemy_kill("c035")
	Meta.add_enemy_kill("c018")
	Meta.add_enemy_kill("c012")
	Meta.add_enemy_kill("c037")
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
		# 刀客正式资料：四个命名招式均有来历，山民被动有机制与来历，技能 5 不再出现。
		var sword_labels: Array = []
		var sword_lore_ok := true
		var sword_cd_ok := true
		var sword_rising_ok := false
		for i in mini(4, codex._acts.size()):
			var action: Dictionary = codex._acts[i]
			var label := str(action["label"])
			sword_labels.append(label)
			var text: String = codex._desc_text(action, str(action["anims"][0]))
			sword_lore_ok = sword_lore_ok and text.contains("来历：") and not text.contains("【待定】")
			if label == "螺旋鞭":
				sword_cd_ok = sword_cd_ok and is_equal_approx(float(codex._cd_for(action)), 9.6)
			elif label == "升龙刀":
				sword_cd_ok = sword_cd_ok and is_equal_approx(float(codex._cd_for(action)), 14.4)
				sword_rising_ok = text.contains("0.87 秒蓄势") and text.contains("2 点伤害并短暂击飞") and text.contains("14.4 秒")
			elif label == "双镰":
				sword_cd_ok = sword_cd_ok and is_equal_approx(float(codex._cd_for(action)), 7.2)
		p("刀客四招=%s 来历完整=%s 特殊招9.6/14.4/7.2秒冷却=%s 升龙刀短击飞文案=%s（期望 亡命三刀/螺旋鞭/升龙刀/双镰，全 true）" % [str(sword_labels), sword_lore_ok, sword_cd_ok, sword_rising_ok])
		var passive_action: Dictionary = {}
		for action in codex._acts:
			if str(action["kind"]) == "passive":
				passive_action = action
		var passive_text: String = codex._desc_text(passive_action, "") if not passive_action.is_empty() else ""
		p("刀客被动=%s 山民资料完整=%s（期望 山 民 / true）" % [str(passive_action.get("label", "")), passive_text.contains("每 5 秒恢复 1 点") and passive_text.contains("来历：") and not passive_text.contains("【待定】")])
		# 重复点击同一动作不得把 Spine 轨道重置到第 0 帧。
		var preview_state = codex._preview.call("get_animation_state")
		var track = preview_state.call("get_current", 0)
		var track_before := float(track.call("get_track_time")) if track != null else -1.0
		codex._pick(0)
		await get_tree().process_frame
		track = preview_state.call("get_current", 0)
		var track_after := float(track.call("get_track_time")) if track != null else -1.0
		p("图鉴同动作重播保护 %.3f -> %.3f（期望不倒退）" % [track_before, track_after])

		# 蛮兵正式资料：只有三招，连段收尾不拆成第四招；数值、冷却、来历、被动与背景完整。
		codex._select("c017")
		await get_tree().create_timer(0.3).timeout
		var brute_model: Dictionary = codex._model(codex._sel)
		var brute_labels: Array = []
		var brute_lore_ok := true
		var brute_cd_ok := true
		var brute_basic_ok := false
		var brute_chain: Dictionary = {}
		var brute_chain_text := ""
		var brute_passive: Dictionary = {}
		var chain_index := -1
		for i in codex._acts.size():
			var action: Dictionary = codex._acts[i]
			if str(action["kind"]) == "enemy_atk":
				var label := str(action["label"])
				brute_labels.append(label)
				var text: String = codex._desc_text(action, str(action["anims"][0]))
				brute_lore_ok = brute_lore_ok and text.contains("来历：") and not text.contains("【待定】")
				if label == "开天":
					brute_basic_ok = text.contains("0.64 秒") and text.contains("2 点伤害") and text.contains("短击退")
				elif label == "辟地":
					brute_cd_ok = brute_cd_ok and is_equal_approx(float(codex._cd_for(action)), 10.8)
				elif label == "赶山三斧":
					brute_chain = action
					brute_chain_text = text
					chain_index = i
					brute_cd_ok = brute_cd_ok and is_equal_approx(float(codex._cd_for(action)), 19.2)
			elif str(action["kind"]) == "passive":
				brute_passive = action
		var brute_passive_text: String = codex._desc_text(brute_passive, "") if not brute_passive.is_empty() else ""
		var brute_three_ok: bool = brute_labels == ["开天", "辟地", "赶山三斧"]
		var brute_chain_ok: bool = chain_index >= 0 and brute_chain.get("sequence", []) == ["skill03_2", "skill03_3"] \
			and (brute_chain.get("anims", []) as Array).size() == 1 \
			and brute_chain_text.contains("连劈 2 段") and brute_chain_text.contains("各 1 伤") \
			and brute_chain_text.contains("大劈 2 伤") and brute_chain_text.contains("力竭 3 秒")
		var brute_lore_tags: bool = not (brute_model["tags"] as Array).has("站桩") \
			and str(brute_model["lore"]).contains("拖着巨斧") and not str(brute_model["lore"]).contains("从不追击")
		p("蛮兵三招=%s 数量正确=%s 来历完整=%s 独立冷却=%s 开天新判定=%s 连段数值=%s（期望 开天/辟地/赶山三斧，全 true）" % [str(brute_labels), brute_three_ok, brute_lore_ok, brute_cd_ok, brute_basic_ok, brute_chain_ok])
		p("蛮兵背景词条=%s 蛮力资料=%s（期望 true / true）" % [brute_lore_tags, brute_passive_text.contains("被动技能 · 蛮力") and brute_passive_text.contains("每段实际伤害") and brute_passive_text.contains("普通控制") and brute_passive_text.contains("来历：") and not brute_passive_text.contains("【待定】")])

		# 连段预览必须按 skill03_2 -> skill03_3 -> stand 顺序走，不能循环第一小段或当成变式。
		var sequence_first := false
		var sequence_second := false
		var sequence_idle := false
		if chain_index >= 0:
			codex._pick(chain_index)
			var brute_state = codex._preview.call("get_animation_state")
			var brute_track = brute_state.call("get_current", 0)
			sequence_first = brute_track != null and str(brute_track.call("get_animation").call("get_name")) == "skill03_2"
			await get_tree().create_timer(1.4).timeout
			brute_track = brute_state.call("get_current", 0)
			sequence_second = brute_track != null and str(brute_track.call("get_animation").call("get_name")) == "skill03_3"
			await _shot("06b_codex_brute_chain")
			await get_tree().create_timer(1.9).timeout
			brute_track = brute_state.call("get_current", 0)
			sequence_idle = brute_track != null and str(brute_track.call("get_animation").call("get_name")) == "stand"
		p("蛮兵连段顺序预览=%s/%s/%s（期望 true/true/true：前两劈 -> 大劈 -> 待机）" % [sequence_first, sequence_second, sequence_idle])

		# 刺客正式资料：两个逻辑招式分别保留名称、机制与来历，预览分别指向 skill02 / skill01。
		codex._select("c035")
		await get_tree().create_timer(0.3).timeout
		var assassin_model: Dictionary = codex._model(codex._sel)
		var assassin_labels: Array = []
		var assassin_keys: Array = []
		var assassin_visuals_ok := true
		var assassin_lore_ok := true
		var assassin_dart_ok := false
		var assassin_sneak_ok := false
		var assassin_passive: Dictionary = {}
		var dart_index := -1
		var sneak_index := -1
		for i in codex._acts.size():
			var action: Dictionary = codex._acts[i]
			if str(action["kind"]) == "enemy_atk":
				var label := str(action["label"])
				assassin_labels.append(label)
				var action_key := str(action.get("key", ""))
				assassin_keys.append(action_key)
				var expected_visual := "skill02" if action_key == "dart" else "skill01"
				assassin_visuals_ok = assassin_visuals_ok and action.get("anims", []) == [expected_visual]
				var text: String = codex._desc_text(action, str(action["anims"][0]))
				assassin_lore_ok = assassin_lore_ok and text.contains("来历：") and not text.contains("【待定】")
				if label == "镖去":
					dart_index = i
					assassin_dart_ok = text.contains("2 段") and text.contains("连续两镖各造成 1 点伤害") \
						and text.contains("3 秒与 6 秒") and text.contains("整轮命中只附一组割伤")
				elif label == "偷袭":
					sneak_index = i
					assassin_sneak_ok = is_equal_approx(float(codex._cd_for(action)), 14.4) \
						and text.contains("绕至目标身后") and text.contains("2 点基础伤害") and text.contains("0.94 秒")
			elif str(action["kind"]) == "passive":
				assassin_passive = action
		var assassin_passive_text: String = codex._desc_text(assassin_passive, "") if not assassin_passive.is_empty() else ""
		var assassin_model_ok: bool = str(assassin_model["lore"]).contains("剃头匠") and (assassin_model["tags"] as Array).has("流血")
		var assassin_data_ok: bool = assassin_labels == ["镖去", "偷袭"] and assassin_keys == ["dart", "sneak"] \
			and assassin_visuals_ok and assassin_lore_ok and assassin_dart_ok and assassin_sneak_ok
		var assassin_passive_ok: bool = str(assassin_passive.get("label", "")) == "阴 影" \
			and assassin_passive_text.contains("双倍暴击") and assassin_passive_text.contains("割伤等持续伤害不触发此效果") \
			and assassin_passive_text.contains("来历：") and not assassin_passive_text.contains("【待定】")
		p("刺客图鉴 双招/逻辑键/数值/来历=%s 阴影资料=%s 背景与流血词条=%s（期望全 true）" % [assassin_data_ok, assassin_passive_ok, assassin_model_ok])
		var assassin_preview_ok := true
		var assassin_state = codex._preview.call("get_animation_state")
		var assassin_track = assassin_state.call("get_current", 0)
		for action_index in [dart_index, sneak_index]:
			if action_index < 0:
				assassin_preview_ok = false
				continue
			codex._pick(action_index)
			await get_tree().process_frame
			var expected_anim := "skill02" if action_index == dart_index else "skill01"
			assassin_track = assassin_state.call("get_current", 0)
			assassin_preview_ok = assassin_preview_ok and str(codex._current_anim) == expected_anim \
				and assassin_track != null and str(assassin_track.call("get_animation").call("get_name")) == expected_anim
		p("刺客双招skill02/skill01预览=%s（期望 true）" % assassin_preview_ok)
		await _shot("06c_codex_assassin")

		# 双镰正式资料：三招动画、前后射程、特殊机制、嗜血与戏班来历完整。
		codex._select("c018")
		await get_tree().create_timer(0.3).timeout
		var dualsickle_model: Dictionary = codex._model(codex._sel)
		var dualsickle_labels: Array = []
		var dualsickle_indices: Array = []
		var dualsickle_visuals_ok := true
		var dualsickle_lore_ok := true
		var dualsickle_dance_ok := false
		var dualsickle_shatter_ok := false
		var dualsickle_bloom_ok := false
		var dualsickle_passive: Dictionary = {}
		for i in codex._acts.size():
			var action: Dictionary = codex._acts[i]
			if str(action["kind"]) == "enemy_atk":
				var label := str(action["label"])
				dualsickle_labels.append(label)
				dualsickle_indices.append(i)
				var expected_visual := "skill0%d" % (dualsickle_labels.size())
				dualsickle_visuals_ok = dualsickle_visuals_ok and action.get("anims", []) == [expected_visual]
				var text: String = codex._desc_text(action, expected_visual)
				dualsickle_lore_ok = dualsickle_lore_ok and text.contains("来历：") and not text.contains("【待定】")
				if label == "镰舞":
					dualsickle_dance_ok = text.contains("2 段") and text.contains("0.30/0.60 秒") \
						and text.contains("普通流血") and text.contains("持续 3 秒") and text.contains("最多 5 层")
				elif label == "镰碎":
					dualsickle_shatter_ok = is_equal_approx(float(codex._cd_for(action)), 9.6) \
						and text.contains("0.73 秒") and text.contains("5 点伤害") \
						and text.contains("实际失去的生命")
				elif label == "镰意绽花":
					dualsickle_bloom_ok = is_equal_approx(float(codex._cd_for(action)), 14.4) \
						and text.contains("不造成直接伤害") and text.contains("2 点本局生命上限") \
						and text.contains("跨房间保留") and text.contains("50%") and text.contains("被防御时无效")
			elif str(action["kind"]) == "passive":
				dualsickle_passive = action
		var dualsickle_passive_text: String = codex._desc_text(dualsickle_passive, "") if not dualsickle_passive.is_empty() else ""
		var dualsickle_model_ok: bool = str(dualsickle_model["lore"]).contains("双刀伶人") \
			and str(dualsickle_model["lore"]).contains("血月绽花") and (dualsickle_model["tags"] as Array).has("流血")
		var dualsickle_data_ok: bool = dualsickle_labels == ["镰舞", "镰碎", "镰意绽花"] \
			and dualsickle_visuals_ok and dualsickle_lore_ok and dualsickle_dance_ok and dualsickle_shatter_ok and dualsickle_bloom_ok
		var dualsickle_passive_ok: bool = str(dualsickle_passive.get("label", "")) == "嗜 血" \
			and dualsickle_passive_text.contains("永久激活") and dualsickle_passive_text.contains("姿态与步伐改变") \
			and dualsickle_passive_text.contains("永不撤销") and dualsickle_passive_text.contains("来历：") \
			and not dualsickle_passive_text.contains("【待定】")
		p("双镰图鉴 三招/动画/数值/来历=%s 嗜血资料=%s 戏班背景与流血词条=%s（期望全 true）" % [
			dualsickle_data_ok, dualsickle_passive_ok, dualsickle_model_ok])
		var dualsickle_preview_ok: bool = dualsickle_indices.size() == 3
		var dualsickle_state = codex._preview.call("get_animation_state")
		for i in dualsickle_indices.size():
			codex._pick(dualsickle_indices[i])
			await get_tree().process_frame
			var expected_anim := "skill0%d" % (i + 1)
			var dualsickle_track = dualsickle_state.call("get_current", 0)
			dualsickle_preview_ok = dualsickle_preview_ok and str(codex._current_anim) == expected_anim \
				and dualsickle_track != null and str(dualsickle_track.call("get_animation").call("get_name")) == expected_anim
		p("双镰三招skill01/skill02/skill03预览=%s（期望 true）" % dualsickle_preview_ok)
		await _shot("06d_codex_dualsickle")

		# 青笠正式资料：双剑斩、旋斩、剑意凝华与听雨阁剑仆背景。
		codex._select("c012")
		await get_tree().create_timer(0.3).timeout
		var qingli_model: Dictionary = codex._model(codex._sel)
		var qingli_labels: Array = []
		var qingli_indices: Array = []
		var qingli_visuals_ok := true
		var qingli_lore_ok := true
		var qingli_dual_ok := false
		var qingli_spin_ok := false
		var qingli_passive: Dictionary = {}
		for i in codex._acts.size():
			var action: Dictionary = codex._acts[i]
			if str(action["kind"]) == "enemy_atk":
				var label := str(action["label"])
				qingli_labels.append(label)
				qingli_indices.append(i)
				var expected_visual := "skill0%d" % (qingli_labels.size())
				qingli_visuals_ok = qingli_visuals_ok and action.get("anims", []) == [expected_visual]
				var text: String = codex._desc_text(action, expected_visual)
				qingli_lore_ok = qingli_lore_ok and text.contains("来历：") and not text.contains("【待定】")
				if label == "双剑斩":
					qingli_dual_ok = text.contains("2 段") and text.contains("1/2 伤") \
						and text.contains("基础 1/2 点") and text.contains("持续 3 秒") and text.contains("剑意")
				elif label == "旋斩":
					qingli_spin_ok = is_equal_approx(float(codex._cd_for(action)), 12.0) \
						and text.contains("0.89 秒") and text.contains("基础 2 点") \
						and text.contains("冷却 12 秒") and text.contains("8 秒无法使用 Shift 闪避")
			elif str(action["kind"]) == "passive":
				qingli_passive = action
		var qingli_passive_text: String = codex._desc_text(qingli_passive, "") if not qingli_passive.is_empty() else ""
		var qingli_data_ok: bool = qingli_labels == ["双剑斩", "旋斩"] and qingli_visuals_ok and qingli_lore_ok and qingli_dual_ok and qingli_spin_ok
		var qingli_passive_ok: bool = str(qingli_passive.get("label", "")) == "剑 意" \
			and qingli_passive_text.contains("剑意凝华") and qingli_passive_text.contains("同步分身") \
			and qingli_passive_text.contains("无敌") and qingli_passive_text.contains("不再繁殖") \
			and qingli_passive_text.contains("淡青水墨虚影") and qingli_passive_text.contains("淡青墨环") \
			and not qingli_passive_text.contains("丝线") and qingli_passive_text.contains("本体死亡即消失") \
			and not qingli_passive_text.contains("【待定】")
		var qingli_model_ok: bool = str(qingli_model["lore"]).contains("听雨阁") and str(qingli_model["lore"]).contains("剑仆") \
			and (qingli_model["tags"] as Array).has("分身")
		p("青笠图鉴 两招/动画/数值/来历=%s 剑意凝华资料=%s 剑仆背景与分身词条=%s（期望全 true）" % [
			qingli_data_ok, qingli_passive_ok, qingli_model_ok])
		var qingli_preview_ok: bool = qingli_indices.size() == 2
		var qingli_state = codex._preview.call("get_animation_state")
		for i in qingli_indices.size():
			codex._pick(qingli_indices[i])
			await get_tree().process_frame
			var expected_anim := "skill0%d" % (i + 1)
			var qingli_track = qingli_state.call("get_current", 0)
			qingli_preview_ok = qingli_preview_ok and str(codex._current_anim) == expected_anim \
				and qingli_track != null and str(qingli_track.call("get_animation").call("get_name")) == expected_anim
		p("青笠双招skill01/skill02预览=%s（期望 true）" % qingli_preview_ok)
		await _shot("06e_codex_qingli")

		# 青魇剑主：四招、藏剑三变式、祭剑双演出，以及带完整前扑回斩的魔爆被动。
		codex._select("c037")
		await get_tree().create_timer(0.3).timeout
		var qingyan_model: Dictionary = codex._model(codex._sel)
		var qingyan_labels: Array = []
		var qingyan_lore_ok := true
		var qingyan_mechanics_ok := true
		var qingyan_cang: Dictionary = {}
		var qingyan_limit: Dictionary = {}
		var qingyan_passive: Dictionary = {}
		var qingyan_cang_index := -1
		var qingyan_limit_index := -1
		var qingyan_passive_index := -1
		for i in codex._acts.size():
			var action: Dictionary = codex._acts[i]
			var label := str(action["label"])
			if str(action["kind"]) == "enemy_atk":
				qingyan_labels.append(label)
				var text: String = codex._desc_text(action, str(action["anims"][0]))
				qingyan_lore_ok = qingyan_lore_ok and text.contains("来历：") and not text.contains("【待定】")
				if label == "亭台剑":
					qingyan_mechanics_ok = qingyan_mechanics_ok and text.contains("1/1/2") and text.contains("0.98 秒")
				elif label == "转":
					qingyan_mechanics_ok = qingyan_mechanics_ok and text.contains("击退") and text.contains("永久 +1")
				elif label == "藏剑式":
					qingyan_cang = action
					qingyan_cang_index = i
					qingyan_mechanics_ok = qingyan_mechanics_ok and text.contains("1/2/3") and text.contains("割伤") \
						and action.get("anims", []) == ["skill05", "skill06", "skill01-cankao"]
				elif label == "断楹祭剑":
					qingyan_limit = action
					qingyan_limit_index = i
					qingyan_mechanics_ok = qingyan_mechanics_ok and text.contains("回满生命") and text.contains("每段实际伤害") \
						and action.get("anims", []) == ["skill04", "skill04-cankao"]
			elif str(action["kind"]) == "passive":
				qingyan_passive = action
				qingyan_passive_index = i
		var qingyan_passive_text: String = codex._desc_text(qingyan_passive, "") if not qingyan_passive.is_empty() else ""
		var qingyan_data_ok: bool = str(qingyan_model.get("title", "")) == "青魇剑主" \
			and qingyan_labels == ["亭台剑", "转", "藏剑式", "断楹祭剑"] and qingyan_lore_ok and qingyan_mechanics_ok \
			and str(qingyan_model.get("lore", "")).contains("青亭") and str(qingyan_model.get("lore", "")).contains("绿色魔剑") \
			and (qingyan_model.get("tags", []) as Array).has("妖异")
		var qingyan_passive_ok: bool = str(qingyan_passive.get("label", "")) == "魔 爆" \
			and qingyan_passive.get("anims", []) == ["transform"] and bool(qingyan_passive.get("death_finisher", false)) \
			and qingyan_passive_text.contains("魔化前扑并回斩") and qingyan_passive_text.contains("下一次冷却永久增加 1 秒") \
			and qingyan_passive_text.contains("来历：") and not qingyan_passive_text.contains("【待定】")
		p("青魇图鉴 新名/背景/四招/数值与来历=%s 魔爆资料与收尾=%s（期望全 true）" % [qingyan_data_ok, qingyan_passive_ok])

		var qingyan_pool_ok: bool = qingyan_cang_index >= 0 and qingyan_limit_index >= 0
		if qingyan_cang_index >= 0:
			codex._pick(qingyan_cang_index)
			await get_tree().process_frame
			var cang_anims: Array = [str(codex._current_anim)]
			codex._cycle_pool(1)
			cang_anims.append(str(codex._current_anim))
			codex._cycle_pool(1)
			cang_anims.append(str(codex._current_anim))
			qingyan_pool_ok = qingyan_pool_ok and cang_anims == ["skill05", "skill06", "skill01-cankao"]
		if qingyan_limit_index >= 0:
			codex._pick(qingyan_limit_index)
			await get_tree().process_frame
			var limit_first := str(codex._current_anim)
			codex._cycle_pool(1)
			qingyan_pool_ok = qingyan_pool_ok and limit_first == "skill04" and str(codex._current_anim) == "skill04-cankao"
		p("青魇藏剑三变式与祭剑双动画切换=%s（期望 true）" % qingyan_pool_ok)

		var qingyan_finisher_ok := false
		var qingyan_return_ok := false
		if qingyan_passive_index >= 0:
			codex._pick(qingyan_passive_index)
			await get_tree().process_frame
			var origin: Vector2 = codex._preview.position
			var held: bool = bool(codex._preview.get_meta("codex_hold_last", false)) and str(codex._current_anim) == "transform"
			await get_tree().create_timer(3.50).timeout
			qingyan_finisher_ok = held and str(codex._current_anim) == "transform" \
				and absf(codex._preview.rotation) > 0.01 and codex._preview.position.x > origin.x + 1.0
			await _shot("06f_codex_qingyan_burst")
			await get_tree().create_timer(0.65).timeout
			qingyan_return_ok = str(codex._current_anim) == "stand" and is_equal_approx(codex._preview.rotation, 0.0) \
				and codex._preview.position.distance_to(origin) < 0.1
		p("青魇魔爆 停末帧并前扑回斩=%s 演完回待机=%s（期望全 true）" % [qingyan_finisher_ok, qingyan_return_ok])

		# 全图鉴玩家文案审计：只检查最终展示文本，内部动画键与判定配置可以继续存在。
		var forbidden: Array = ["号动画", "号变身", "【待定】", "第 6 阶段", "低权重", "前后判定", "出招时刻即判定命中", "px", "skill01", "skill02", "skill03", "skill04", "skill05", "skill06", "transform", "cankao"]
		var clean_text := true
		for id in codex.ENEMY_ORDER + codex.BossTypes.ROSTER:
			var is_boss: bool = codex.BossTypes.ROSTER.has(id)
			var data: Dictionary = codex.BossTypes.get_boss(id) if is_boss else codex.EnemyTypes.get_type(id)
			# 直接生成全部动作资料，未收录的 Boss 也必须接受审计，不能空遍历假通过。
			for action in codex._enemy_actions(data, is_boss, str(id)):
				var text: String = codex._desc_text(action, str((action.get("anims", []) as Array)[0]) if not (action.get("anims", []) as Array).is_empty() else "")
				for term in forbidden:
					if text.contains(str(term)):
						clean_text = false
						p("文案穿帮 %s / %s / %s" % [str(id), str(action.get("label", "")), str(term)])
		p("全部敌人与Boss图鉴无开发术语/资源键/占位文案=%s（期望 true）" % clean_text)

		# 已收录的 Boss 详情（c032 三段变身）；无正式来历的区块应直接省略。
		codex._select("c032")
		await get_tree().create_timer(0.3).timeout
		await _shot("07_codex_boss")
		# 化身页：切页后默认选中双刺
		codex._switch_tab(1)
		await get_tree().create_timer(0.3).timeout
		p("切到化身页 -> 选中=%s（期望 c021）" % str(codex._sel))
		await _shot("08_codex_form")
		for id in codex.Skulls.ORDER:
			for action in codex._form_actions(codex.Skulls.get_profile(str(id))):
				var text: String = codex._desc_text(action, str((action.get("anims", []) as Array)[0]) if not (action.get("anims", []) as Array).is_empty() else "")
				for term in forbidden:
					if text.contains(str(term)):
						clean_text = false
						p("化身文案穿帮 %s / %s / %s" % [str(id), str(action.get("label", "")), str(term)])
		p("全部化身图鉴无开发术语/资源键/占位文案=%s（期望 true）" % clean_text)
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
		var has_empty_passive := false
		for action in codex._acts:
			has_empty_passive = has_empty_passive or str(action.get("kind", "")) == "passive"
		p("银夜变式数：普攻2=%d K=%d I=%d 空白被动已隐藏=%s（期望 2 / 2 / 1 / true）" % [
			(codex._acts[atk2]["anims"] as Array).size() if atk2 >= 0 else 0,
			(codex._acts[k]["anims"] as Array).size() if k >= 0 else 0,
			(codex._acts[i_skill]["anims"] as Array).size() if i_skill >= 0 else 0,
			str(not has_empty_passive)])
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
		# 同一页面按 1920×1080 等比例放大，复核 MSDF 字体在实际拉伸后的清晰度。
		get_window().size = Vector2i(1920, 1080)
		await get_tree().create_timer(0.25).timeout
		await _shot("09b_codex_pool_1920")
		get_window().size = Vector2i(1280, 720)
		await get_tree().create_timer(0.2).timeout
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
