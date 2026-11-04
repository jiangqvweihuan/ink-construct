extends Node

## UI 冒烟测试：主菜单 -> 设置面板 -> 化身谱（含购买后重建）-> 图鉴（收录 / 点击演示 / 变式轮播 / 切页）
## -> 截图 -> 退出。化身谱部分用真实鼠标点「返回」：_refresh 重建后点击音节点必须还在。

const OUT_DIR := "res://tests/out/"

const Settings = preload("res://scripts/ui/settings.gd") # 改键回归用
const StatusCodex = preload("res://scripts/ui/status_codex.gd")

## 独立完整性基线：不能用目录自己生成的 ID 集合代替预期。
const EXPECTED_STATUS_IDS := [
	"shield", "war_block", "bell", "perfect_dodge", "lifesteal", "start_guard",
	"parry", "bell_shell", "awaken", "form_buff", "confidence", "stop_buff",
	"dash_attack", "meditation", "buddha", "blood_dance", "room_awaken_damage",
	"frost", "feathers", "daggers", "bait", "precepts", "air_follow", "sword_seals",
	"return_mark", "skill_cancel_ready", "wind_final", "stolen_wall_guard", "stolen_era",
	"regen", "bloodthirst", "sword_intent", "bloom_cooldown", "limit_cut", "turn_stacks", "red_scapegoat",
	"ming_heroic", "divine_favor", "fen_awaken", "eye_passive",
	"bleed", "cut", "jump_seal", "dash_seal", "stun", "root", "slow", "time_stop",
	"poison", "frenzy", "charm", "grudge", "six_senses", "mind_shock", "transferred_debuffs",
	"red_butterfly", "branch_zone", "plum_marks", "openings", "k_sealed", "seal_targets", "time_marks",
	"cripple", "mo_ting_burn", "fen_ding_burn", "vulnerable", "passive_seal", "sui_yue_pressure",
	"wu_che_wanted", "mo_ting_grab", "ming_zhong_hold", "ming_zhong_holy", "stolen_passives",
	"room_cd_curse", "sword_sect",
]

var _log: FileAccess
var _menu: Node


class SwapPlayerStub:
	extends Node
	var skull_id := "c021"

	func swap_skull(id: String) -> void:
		skull_id = id

func p(msg) -> void:
	print("[UI] ", msg)
	if _log:
		_log.store_line("[UI] " + str(msg))
		_log.flush()

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	get_tree().create_timer(120.0).timeout.connect(func():
		p("TIMEOUT")
		get_tree().quit(2)
	)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_log = FileAccess.open("res://tests/ui_test.log", FileAccess.WRITE)

	_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(_menu)
	await get_tree().create_timer(0.6).timeout
	_assert_sfx_buses(_menu)
	await _shot("01_main_menu")
	await _click(Vector2(1180, 520))
	var click_root := ScreenFX.get_node_or_null("ClickRoot")
	assert(click_root != null and click_root.get_child_count() > 0, "菜单真实点击必须创建 E54068")
	var click_fx = click_root.get_child(click_root.get_child_count() - 1)
	assert(click_fx.sprite != null, "菜单点击特效必须包含真实 SpineSprite")
	assert(click_fx.sprite.get("skeleton_data_res") != null, "菜单点击 Spine 骨架必须已挂载")
	assert(click_fx.sprite.get("skeleton_data_res").call("find_animation", "action1") != null, "菜单点击必须使用 E54068/action1")
	assert(click_fx.process_mode == Node.PROCESS_MODE_ALWAYS, "暂停 UI 的点击特效必须继续播放")
	assert(get_tree().root.get_node("ScreenFX") == ScreenFX, "点击特效必须复用唯一 ScreenFX autoload")
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "可点击菜单界面必须显示自定义鼠标")
	_assert_cursor_hotspot()
	await get_tree().create_timer(0.18).timeout
	await _shot("01a_menu_click")

	# 致谢：左侧竖排入口 → 滚动名单（打开后必须真的在上移）
	_menu._open_credits()
	await get_tree().create_timer(0.5).timeout
	var credits = _find_panel("credits_panel.gd")
	p("致谢打开=%s（期望 true）" % (credits != null))
	if credits != null:
		var has_placeholder := false
		for entry in credits.CREDITS:
			var text := str(entry["s"])
			has_placeholder = has_placeholder or text.contains("【") or text.contains("】")
		p("致谢模板占位已清空=%s（期望 true）" % (not has_placeholder))
		p("致谢滚动 offset=%.1f（期望 > 0）" % credits._offset)
		await _shot("01b_credits")
		# 致谢期间点主菜单区域不能穿透（全屏遮罩必须吃掉点击）
		await _click(Vector2(200, 624))
		p("致谢中点击菜单区 -> 开始面板=%s（期望 false）" % (_find_panel("start_panel.gd") != null))
		credits.queue_free()
		await get_tree().process_frame

	# 设置：三页签截图 + 改键/冲突/Esc 取消（persist 关掉，不写玩家配置）
	Settings.persist = false
	Settings.reset_binds()
	_menu._open_settings()
	await get_tree().create_timer(0.4).timeout
	var sp = _find_panel("settings_panel.gd")
	p("设置打开=%s（期望 true）" % (sp != null))
	await _shot("02_settings_audio")
	if sp != null:
		_assert_sfx_buses(sp)
		sp._switch_tab("画面")
		await get_tree().process_frame
		await _shot("02b_settings_video")
		sp._switch_tab("操作")
		await get_tree().process_frame
		await _shot("02c_settings_keys")
		# 面板内先改草稿：按钮显示 G，但关闭前 InputMap 仍保持 Space。
		sp._start_capture("jump")
		await _press_key(KEY_G)
		p("改键草稿 jump 按钮=%s 草稿=%s 实键=%s（期望 G / G / 空）" % [sp._key_btns["jump"].text, sp._draft_label("jump"), Settings.action_label("jump")])
		# 冲突检测同样读取草稿，闪避不能抢跳跃刚选择的 G。
		sp._start_capture("dash")
		await _press_key(KEY_G)
		p("冲突绑定被拒 dash 草稿=%s hint=%s（期望 Sh / 非空）" % [sp._draft_label("dash"), sp._hint.text])
		# 第一次 Esc 只取消录入，第二次 Esc 关闭并统一应用。
		sp._start_capture("dash")
		await _press_key(KEY_ESCAPE)
		p("Esc 取消录入 dash 草稿=%s 面板存在=%s（期望 Sh / true）" % [sp._draft_label("dash"), is_instance_valid(sp)])
		await _press_key(KEY_ESCAPE)
		await get_tree().create_timer(0.2).timeout
		p("Esc 关闭设置并应用 jump=%s 面板=%s（期望 G / false）" % [Settings.action_label("jump"), _find_panel("settings_panel.gd") != null])
	# 叉号走同一条关闭应用路径，且显示正常 × 而非“启”。
	_menu._open_settings()
	await get_tree().create_timer(0.2).timeout
	await _click(Vector2(981, 101))
	await get_tree().create_timer(0.2).timeout
	p("叉号关闭设置 面板=%s（期望 false）" % (_find_panel("settings_panel.gd") != null))

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
		_assert_sfx_buses(forms)
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
		p("化身谱已返回总览")
		await get_tree().create_timer(0.2).timeout
		forms._refresh() # 购买后走的重建路径
		p("化身谱总览已重建")
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
		_assert_sfx_buses(shop)
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
	Meta.add_enemy_kill("c008")
	Meta.add_enemy_kill("c032")
	_menu._open_codex()
	await get_tree().create_timer(0.5).timeout
	var codex = _find_panel("codex_panel.gd")
	p("图鉴打开=%s（期望 true）" % (codex != null))
	await _shot("05_codex_enemy")

	if codex != null:
		_assert_sfx_buses(codex)
		assert(codex._medal_fx == null, "普通刀客图鉴不得显示特殊勋章")
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

		# 有原画的首领默认展示完整立绘；切到动作后才创建 Spine 与招式按钮。
		codex._select("c009")
		await get_tree().create_timer(0.3).timeout
		p("墨霆图鉴默认原画=%s 完整容纳=%s 动作未提前加载=%s（期望全 true）" % [
			is_instance_valid(codex._portrait) and codex._portrait.texture != null,
			is_instance_valid(codex._portrait) and codex._portrait.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
			codex._preview == null and codex._acts.is_empty()])
		await _shot("06g_codex_mo_ting_portrait")
		codex._set_portrait_view(false)
		await get_tree().create_timer(0.3).timeout
		p("墨霆切到动作=%s 招式数=%d（期望 true / >0）" % [is_instance_valid(codex._preview), codex._acts.size()])
		codex._set_portrait_view(true)
		await get_tree().create_timer(0.3).timeout
		p("墨霆切回原画=%s 动作已卸载=%s（期望 true / true）" % [
			is_instance_valid(codex._portrait), codex._preview == null and codex._acts.is_empty()])
		codex._select("c008")
		await get_tree().create_timer(0.3).timeout
		p("碎岳图鉴默认原画=%s（期望 true）" % (is_instance_valid(codex._portrait) and codex._portrait.texture != null))
		await _shot("06h_codex_sui_yue_portrait")
		codex._set_portrait_view(false)
		await get_tree().create_timer(0.3).timeout
		p("碎岳切到动作=%s 招式数=%d（期望 true / >0）" % [is_instance_valid(codex._preview), codex._acts.size()])

		# 已收录的 Boss 详情（c032 四招与双被动）；无正式来历的区块应直接省略。
		codex._select("c032")
		await get_tree().create_timer(0.3).timeout
		await _shot("07_codex_boss")
		var mz_labels: Array = []
		var mz_passives := 0
		var mz_lore_ok := true
		for action in codex._acts:
			if str(action["kind"]) == "enemy_atk":
				mz_labels.append(str(action["label"]))
				var text: String = codex._desc_text(action, str(action["anims"][0]))
				mz_lore_ok = mz_lore_ok and text.contains("来历：") and not text.contains("【待定】")
			elif str(action["kind"]) == "passive":
				mz_passives += 1
				var text: String = codex._desc_text(action, "")
				mz_lore_ok = mz_lore_ok and text.contains("来历：") and not text.contains("【待定】")
		var mz_model: Dictionary = codex._model(codex._sel)
		var mz_model_ok: bool = str(mz_model["lore"]).contains("女武神") and not str(mz_model["lore"]).contains("钟馗")
		var mz_scale_ok: bool = is_equal_approx(float(mz_model["view_scale"]), 0.62) and is_equal_approx(float(codex._preview.scale.x), 0.62)
		p("鸣钟图鉴 四招=%s 双被动=%s 来历完整=%s 女武神背景=%s 正常大小=%s（期望 坠锋/四响/旋征/神骸鸣钟，其余全 true）" % [str(mz_labels), mz_passives == 2, mz_lore_ok, mz_model_ok, mz_scale_ok])
		assert(codex._medal_fx != null and codex._medal_fx.sprite != null, "Boss 图鉴必须创建 E21019 真实 SpineSprite")
		assert(codex._medal_fx.sprite.get("skeleton_data_res") != null, "Boss 勋章骨架必须已挂载")
		_assert_spine_animation(codex._medal_fx, "boss")
		codex._select("c037")
		await get_tree().create_timer(0.3).timeout
		assert(codex._medal_fx != null and codex._medal_fx.sprite != null, "精英图鉴必须创建 E21019 真实 SpineSprite")
		_assert_spine_animation(codex._medal_fx, "elite")
		codex._select("c016")
		await get_tree().create_timer(0.3).timeout
		assert(codex._medal_fx == null, "切回普通怪必须移除特殊勋章")

		# 状态页：主菜单中无 Player / Run 也必须收录并展示全部 75 项。
		await _click(Vector2(1162, 74))
		await get_tree().create_timer(0.2).timeout
		assert(codex._tab == codex.TAB_STATUS and codex._sel == "shield", "状态页真实页签点击必须选中首项")
		assert(codex._preview == null and codex._medal_fx == null and codex._acts.is_empty(), "状态页不得创建角色 Spine、勋章或动作")
		assert(is_instance_valid(codex._status_list) and is_instance_valid(codex._status_detail), "状态页必须创建滚动目录与详情")
		var status_entries: Array = StatusCodex.entries()
		var status_ids: Array = []
		var seen_status := {}
		var expected_status_set := {}
		var status_shape_ok := true
		var buff_count := 0
		var debuff_count := 0
		for id in EXPECTED_STATUS_IDS:
			assert(not expected_status_set.has(id), "独立预期状态 ID 不得重复：" + str(id))
			expected_status_set[id] = true
		assert(EXPECTED_STATUS_IDS.size() == 75, "独立预期状态数必须固定为 75")
		for e in status_entries:
			var id := str(e.get("id", ""))
			var kind := str(e.get("kind", ""))
			status_ids.append(id)
			if id.is_empty() or seen_status.has(id):
				status_shape_ok = false
				p("状态 ID 为空或重复：" + id)
			seen_status[id] = true
			for key in ["id", "kind", "target", "group", "name", "summary", "rules", "sources", "runtime_ids"]:
				if not e.has(key):
					status_shape_ok = false
					p("状态缺字段 %s / %s" % [id, str(key)])
			if not ["buff", "debuff"].has(kind) or not ["player", "enemy", "both"].has(str(e.get("target", ""))):
				status_shape_ok = false
				p("状态分类非法：" + id)
			if kind == "buff":
				buff_count += 1
			elif kind == "debuff":
				debuff_count += 1
			if str(e.get("group", "")).strip_edges().is_empty() or str(e.get("name", "")).strip_edges().is_empty() \
				or str(e.get("summary", "")).strip_edges().is_empty():
				status_shape_ok = false
				p("状态标题、分组或摘要为空：" + id)
			for key in ["rules", "sources", "runtime_ids"]:
				if not (e.get(key, []) is Array) or (e.get(key, []) as Array).is_empty():
					status_shape_ok = false
					p("状态数组为空或类型错误 %s / %s" % [id, key])
		for id in EXPECTED_STATUS_IDS:
			assert(seen_status.has(id), "状态目录缺少预期条目：" + str(id))
		for id in status_ids:
			assert(expected_status_set.has(id), "状态目录出现未预期条目：" + str(id))
		assert(status_ids.size() == EXPECTED_STATUS_IDS.size(), "状态目录总数必须与独立预期双向一致")
		assert(buff_count == 40 and debuff_count == 35, "状态目录必须为 40 增益 + 35 减益")
		assert(status_shape_ok, "全部状态的结构、标题、摘要、规则、来源与运行时映射必须完整")
		var status_unlocked_ok := true
		for e in codex._entries():
			status_unlocked_ok = status_unlocked_ok and not bool(e["locked"])
		assert(status_unlocked_ok, "全部状态必须默认解锁，不读取击杀或化身解锁")
		assert(codex._status_buttons.size() == status_entries.size(), "状态按钮数必须等于目录总数")
		assert(codex._status_list.get_v_scroll_bar().max_value > codex._status_list.get_v_scroll_bar().page, "75 项目录必须可纵向滚动")
		p("状态目录 75 项双向完整=%s 结构=%s 增益/减益=%d/%d 全解锁=%s 按钮=%d（期望全 true / 40/35 / 75）" % [
			str(status_ids.size() == EXPECTED_STATUS_IDS.size()), status_shape_ok, buff_count, debuff_count,
			status_unlocked_ok, codex._status_buttons.size()])
		await _shot("07i_codex_status")

		# 逐项触发真实按钮 pressed 信号；每次重建后核对标题、摘要、每条规则和每个来源。
		var status_ui_ok := true
		for i in status_entries.size():
			var e: Dictionary = status_entries[i]
			var id := str(e["id"])
			var button: TextureButton = codex._status_buttons[i]
			assert(str(button.get_meta("status_id", "")) == id, "状态按钮顺序必须与目录一致：" + id)
			button.pressed.emit()
			await get_tree().process_frame
			await get_tree().process_frame
			if not is_instance_valid(codex._status_detail):
				status_ui_ok = false
				p("状态详情未重建：" + id)
				continue
			var detail_text: String = codex._status_detail.get_parsed_text()
			var item_ok: bool = codex._sel == id and detail_text.contains(str(e["name"])) and detail_text.contains(str(e["summary"]))
			for rule in e["rules"]:
				item_ok = item_ok and detail_text.contains(str(rule))
			for source in e["sources"]:
				item_ok = item_ok and detail_text.contains(str(source))
			item_ok = item_ok and codex._preview == null and codex._medal_fx == null and codex._acts.is_empty()
			if not item_ok:
				status_ui_ok = false
				p("状态 UI 条目缺漏：" + id)
		assert(status_ui_ok, "75 项状态必须逐项可选且完整显示全部规则与来源")
		p("状态页全条目真实按钮遍历与详情覆盖=%s（期望 true / 75 项）" % status_ui_ok)

		# 选择另一项会重建界面，左侧滚动位置不能跳回顶部。
		codex._select("shield")
		await get_tree().process_frame
		await get_tree().process_frame
		codex._status_list.scroll_vertical = 900
		await get_tree().process_frame
		var status_scroll_before: int = codex._status_list.scroll_vertical
		assert(status_scroll_before > 0, "状态目录必须能实际滚离顶部")
		var second_status: TextureButton = codex._status_buttons[1]
		second_status.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var status_scroll_after: int = codex._status_list.scroll_vertical
		assert(status_scroll_after == status_scroll_before, "状态选择重建后必须保持目录滚动位置")
		p("状态目录滚动保持 %d -> %d（期望相等且 >0）" % [status_scroll_before, status_scroll_after])

		# 自动挑选文字最多的一项，确认详情确实能滚动到底部。
		var longest_status := ""
		var longest_length := -1
		for e in status_entries:
			var text_length := str(e["summary"]).length()
			for rule in e["rules"]:
				text_length += str(rule).length()
			for source in e["sources"]:
				text_length += str(source).length()
			if text_length > longest_length:
				longest_length = text_length
				longest_status = str(e["id"])
		codex._select(longest_status)
		await get_tree().process_frame
		await get_tree().process_frame
		var detail_scroll: VScrollBar = codex._status_detail.get_v_scroll_bar()
		assert(detail_scroll.max_value > detail_scroll.page, "最长状态详情必须提供真实纵向滚动")
		detail_scroll.value = detail_scroll.max_value
		await get_tree().process_frame
		assert(detail_scroll.value > 0, "状态长详情必须能实际滚动")
		p("状态长详情滚动=%s 内容长度=%d 滚动值=%.1f（期望可滚动且 >0）" % [longest_status, longest_length, detail_scroll.value])
		await _shot("07j_codex_status_long")

		# 切回敌人页后再进入化身页，原有角色回归继续执行。
		codex._switch_tab(codex.TAB_ENEMY)
		await get_tree().create_timer(0.3).timeout
		assert(codex._sel == "c016" and codex._status_list == null and codex._status_detail == null, "离开状态页必须恢复敌人条目并清理状态控件")
		assert(not codex._acts.is_empty() and codex._medal_fx == null, "状态页返回后普通敌人的动作与勋章规则必须保留")
		# 化身页：切页后默认选中双刺
		codex._switch_tab(1)
		await get_tree().create_timer(0.3).timeout
		p("切到化身页 -> 选中=%s（期望 c021）" % str(codex._sel))
		await _shot("08_codex_form")
		# 缺原画的化身仍直接展示 Spine，不留空展示框。
		codex._select("c013")
		await get_tree().create_timer(0.3).timeout
		p("力僧缺原画回退：原画为空=%s 动作可用=%s（期望 true / true）" % [
			codex._portrait == null, is_instance_valid(codex._preview) and not codex._acts.is_empty()])
		await _shot("08a_codex_form_fallback")
		Meta.clears = 1
		codex._select("z000")
		await get_tree().create_timer(0.3).timeout
		p("剑仙图鉴默认原画=%s 动作未提前加载=%s（期望 true / true）" % [
			is_instance_valid(codex._portrait) and codex._portrait.texture != null,
			codex._preview == null and codex._acts.is_empty()])
		await _shot("08a_codex_sword_portrait")
		Meta.clears = 5
		Meta.kills = 300
		codex._select("z002")
		await get_tree().create_timer(0.3).timeout
		p("绛弦图鉴默认原画=%s 动作未提前加载=%s（期望 true / true）" % [
			is_instance_valid(codex._portrait) and codex._portrait.texture != null,
			codex._preview == null and codex._acts.is_empty()])
		await _shot("08b_codex_pipa_portrait")
		codex._set_portrait_view(false)
		await get_tree().create_timer(0.3).timeout
		await _shot("08b_codex_pipa")
		var pipa_passives: Array = []
		for action in codex._acts:
			if str(action.get("kind", "")) == "passive":
				pipa_passives.append(str(action.get("label", "")))
		p("绛弦图鉴三被动=%s（期望 红尘/红粉骷髅/神伤）" % str(pipa_passives))
		# 六化身：逐招核对正式名，所有现有普攻与技能都必须有数值、机制和来历。
		var expected_form_moves := {
			"c021": {"attack": ["绛衣试水", "回燕剪翎", "红绫卷霜"], "skill": ["流光度影", "罗刹旋舞", "红缨缚雁"]},
			"c013": {"attack": ["撞钟", "碎磐"], "skill": ["钟荡群山", "金刚怒目", "立地听禅"]},
			"c023": {"attack": ["疏枝引鹤"], "skill": ["梅间回雪"]},
			"z000": {"attack": ["松间问鹤", "流云回锋", "骤雨听剑", "玉宇挑月"], "skill": ["千锋回雪", "月华斩", "步月登霄", "一剑惊鸿", "剑奉山河", "惊鸿燕返"]},
			"z002": {"attack": ["冰弦初响", "促柱追声", "急雨敲窗", "余音入魔"], "skill": ["踏弦", "黍离", "摄心", "红尘劫", "八音断识", "心魔引"]},
			"z003": {"attack": ["袖里青蛇", "揽月上霄", "断雁回风"], "skill": ["崩云", "飞星送客", "万籁停晷", "长夜明火", "舜华斩", "天倾"]},
		}
		var form_names_ok := true
		var form_details_ok := true
		var form_forbidden: Array = forbidden + [
			"无名式", "普攻 1", "普攻 2", "普攻 3", "普攻 4",
			"技能 K", "技能 L", "技能 U", "技能 I", "技能 O", "技能 P", "O · ",
			"skill", "atk", "res://", "user://", "hit_at", "cooldown", "damage", "range", "【待补】", "TODO",
		]
		for id in codex.Skulls.ORDER:
			var labels := {"attack": [], "skill": []}
			for action in codex._form_actions(codex.Skulls.get_profile(str(id)), str(id)):
				var kind := str(action.get("kind", ""))
				var text: String = codex._desc_text(action, str((action.get("anims", []) as Array)[0]) if not (action.get("anims", []) as Array).is_empty() else "")
				for term in form_forbidden:
					if text.contains(str(term)):
						clean_text = false
						p("化身文案穿帮 %s / %s / %s" % [str(id), str(action.get("label", "")), str(term)])
				if kind != "attack" and kind != "skill":
					continue
				(labels[kind] as Array).append(str(action.get("label", "")))
				var details_ok := not str(action.get("num", "")).strip_edges().is_empty() \
					and not str(action.get("mech", "")).strip_edges().is_empty() \
					and not str(action.get("lore", "")).strip_edges().is_empty() \
					and text.contains("数值：") and text.contains("机制：") and text.contains("来历：")
				if not details_ok:
					form_details_ok = false
					p("化身资料缺漏 %s / %s" % [str(id), str(action.get("label", ""))])
			var expected: Dictionary = expected_form_moves.get(str(id), {})
			for kind in ["attack", "skill"]:
				if labels[kind] != expected.get(kind, []):
					form_names_ok = false
					p("化身正式名不符 %s / %s：%s" % [str(id), str(kind), str(labels[kind])])
		p("六化身全部现有普攻/技能正式名=%s 数值/机制/来历完整=%s（期望全 true）" % [form_names_ok, form_details_ok])
		p("全部化身图鉴无旧标签/开发术语/资源键/占位文案=%s（期望 true）" % clean_text)
		# 影殇变式池：揽月上霄与崩云各留 2 条，长夜明火只留 1 条；三条固有被动完整显示。
		Meta.clears = 3
		Meta.kills = 150
		codex._select("z003")
		await get_tree().create_timer(0.3).timeout
		p("影殇图鉴默认原画=%s 动作未提前加载=%s（期望 true / true）" % [
			is_instance_valid(codex._portrait) and codex._portrait.texture != null,
			codex._preview == null and codex._acts.is_empty()])
		await _shot("09_codex_z003_portrait")
		codex._set_portrait_view(false)
		await get_tree().create_timer(0.3).timeout
		var atk2 := -1
		var k := -1
		var i_skill := -1
		var passive_labels: Array = []
		for i in codex._acts.size():
			var label := str(codex._acts[i]["label"])
			if label == "揽月上霄":
				atk2 = i
			elif label == "崩云":
				k = i
			elif label == "长夜明火":
				i_skill = i
			if str(codex._acts[i].get("kind", "")) == "passive":
				passive_labels.append(label)
		p("影殇变式数：揽月上霄=%d 崩云=%d 长夜明火=%d 固有被动=%s（期望 2 / 2 / 1 / 暗夜、血色切割、魅唤）" % [
			(codex._acts[atk2]["anims"] as Array).size() if atk2 >= 0 else 0,
			(codex._acts[k]["anims"] as Array).size() if k >= 0 else 0,
			(codex._acts[i_skill]["anims"] as Array).size() if i_skill >= 0 else 0,
			str(passive_labels)])
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

	# 强化前进：真实点击后立即禁用；同步直接重复调用也只能发出一次 proceed。
	var upgrade = load("res://scenes/ui/upgrade_panel.tscn").instantiate()
	_menu.add_child(upgrade)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_sfx_buses(upgrade)
	var proceed_calls: Array = [0]
	var proceed_disabled_at_emit: Array = [false]
	var before_proceed_audio: Array = _root_audio_players()
	upgrade.proceed.connect(func():
		proceed_calls[0] = int(proceed_calls[0]) + 1
		proceed_disabled_at_emit[0] = upgrade._proceed_button.disabled
		_assert_detached_sfx(_root_sfx_since(before_proceed_audio, upgrade.SFX_CLICK)))
	await _click(Vector2(500, 614))
	assert(int(proceed_calls[0]) == 1, "真实点击前进必须且只能发出一次 proceed")
	assert(upgrade._proceed_button.disabled, "前进后实际按钮必须立即禁用")
	assert(bool(proceed_disabled_at_emit[0]), "proceed 发出前按钮必须已经禁用")
	upgrade._on_proceed()
	assert(int(proceed_calls[0]) == 1, "直接重复调用前进不得再次发出 proceed")
	p("强化前进真实输入/直接重复调用与转场音效断言通过")
	upgrade.queue_free()
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame

	# 换形抽签跨过 0.18 秒后的面板销毁；播放器仍由 root 持有并自行清理。
	var swap_player := SwapPlayerStub.new()
	_menu.add_child(swap_player)
	var swap = load("res://scenes/ui/swap_panel.tscn").instantiate()
	swap.setup(swap_player)
	_menu.add_child(swap)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_sfx_buses(swap)
	Meta.purchases["buyout_c013"] = true
	var before_swap_audio: Array = _root_audio_players()
	swap.select("c013")
	var swap_sfx := _root_sfx_since(before_swap_audio, swap.SFX_SWAP)
	_assert_detached_sfx(swap_sfx)
	assert(swap_player.skull_id == "c013", "换形仍必须调用真实换头入口")
	var expect_swap_sfx_alive := swap_sfx.stream.get_length() > 0.35
	await get_tree().create_timer(0.25).timeout
	assert(not is_instance_valid(swap), "换形面板应按原时序关闭")
	assert(not get_tree().paused, "换形关闭后必须恢复场景")
	if expect_swap_sfx_alive:
		assert(is_instance_valid(swap_sfx), "尚未播完的抽签音效不得随换形面板销毁")
	p("换形抽签跨面板销毁与 SFX 总线断言通过")
	swap_player.queue_free()
	await get_tree().process_frame

	Settings.reset_binds()
	p("ALL DONE")
	get_tree().quit()


func _assert_spine_animation(fx: Node2D, expected: String) -> void:
	var state = fx.sprite.call("get_animation_state")
	var track = state.call("get_current", 0)
	assert(track != null, "特效必须存在当前动画轨道")
	assert(str(track.call("get_animation").call("get_name")) == expected, "特效必须使用实测动画 " + expected)


func _find_panel(script_name: String) -> Node:
	for c in _menu.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with(script_name):
			return c
	return null


func _assert_cursor_hotspot() -> void:
	var image: Image = ScreenFX.MOUSE_CURSOR.get_image()
	assert(image != null and not image.is_empty(), "自定义鼠标源图必须可读取")
	var tip_y := -1
	var tip_left := 0
	var tip_right := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= 0.01:
				continue
			if tip_y < 0:
				tip_y = y
				tip_left = x
			tip_right = x
		if tip_y >= 0:
			break
	assert(tip_y >= 0, "自定义鼠标源图必须包含可见像素")
	var expected := Vector2(roundi(float(tip_left + tip_right) * 0.5), tip_y)
	p("自定义鼠标尖端热点：期望=%s 实际=%s（最上方可见行 x=%d～%d, y=%d）" % [str(expected), str(ScreenFX.CURSOR_HOTSPOT), tip_left, tip_right, tip_y])
	assert(ScreenFX.CURSOR_HOTSPOT == expected, "自定义鼠标点击热点必须位于图标最上方尖端中心")


func _assert_sfx_buses(node: Node) -> void:
	for child in node.get_children():
		if child is AudioStreamPlayer:
			assert(child.bus == "SFX", "%s 必须走 SFX 总线" % child.get_path())
		_assert_sfx_buses(child)


func _root_audio_players() -> Array:
	var players: Array = []
	for child in get_tree().root.get_children():
		if child is AudioStreamPlayer:
			players.append(child)
	return players


func _root_sfx_since(before: Array, stream: AudioStream) -> AudioStreamPlayer:
	for child in get_tree().root.get_children():
		if child is AudioStreamPlayer and not before.has(child) and child.stream == stream:
			return child
	return null


func _assert_detached_sfx(sfx: AudioStreamPlayer) -> void:
	assert(sfx != null, "转场音效必须创建 root 级播放器")
	if sfx == null:
		return
	assert(sfx.get_parent() == get_tree().root, "转场音效不得挂在即将销毁的面板下")
	assert(sfx.bus == "SFX", "转场音效必须走 SFX 总线")
	assert(sfx.process_mode == Node.PROCESS_MODE_ALWAYS, "暂停中转场音效必须继续播放")
	assert(sfx.finished.is_connected(sfx.queue_free), "转场音效结束后必须自行释放")


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
