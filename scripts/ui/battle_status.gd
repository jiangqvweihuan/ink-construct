extends RefCounted

const CodexText = preload("res://scripts/ui/codex_panel.gd")

## 战斗 HUD 与暂停菜单共用的只读状态汇总，不另建一套被动数据。

static func entries(player) -> Array:
	var out: Array = []
	if player == null or not is_instance_valid(player):
		return out
	_add_timed(player, out)
	_add_passives(player, out)
	_add_stolen(out)
	_add_upgrades(out)
	return out


static func _entry(out: Array, id: String, kind: String, title: String, desc: String, value := "", active := true) -> void:
	out.append({"id": id, "kind": kind, "name": title, "desc": desc, "value": value, "active": active})


static func _add_timed(player, out: Array) -> void:
	var shields := int(player.get("_shield_hits"))
	if shields > 0:
		_entry(out, "shield", "buff", "金钟罩", "护体真气，每层挡下一次伤害。", "%d 次 · %.1f 秒" % [shields, float(player.get("_shield_time"))])
	var block := int(player.get("_stolen_block"))
	if block > 0:
		_entry(out, "war_block", "buff", "武神格挡", "格挡值先行承伤，有效命中可以继续积攒。", "%d 点" % block)
	var bell := int(player.get("_stolen_bell"))
	if bell > 0:
		_entry(out, "bell", "buff", "佛曰金钟", "每层可挡两次伤害，层数不设上限。", "%d 层" % int(ceil(bell / 2.0)))
	if bool(player.get("_parry_ready")):
		_entry(out, "parry", "buff", "回环", "可弹开下一次近身攻击。", "就绪")
	if bool(player.get("_bell_shell")):
		_entry(out, "bell_shell", "buff", "反震壳", "碎钟余韵，还能再震开一次伤害。", "就绪")
	var awaken := float(player.get("_awaken_time"))
	if awaken > 0.0:
		_entry(out, "awaken", "buff", "剑意觉醒", "觉醒技已解禁，命中叠剑意，层层增伤。", "%.1f 秒 · %d 层" % [awaken, int(player.get("_awaken_stacks"))])
	var buff := float(player.get("_buff_timer"))
	if buff > 0.0:
		var title := "战斗觉醒"
		if str(player.get("skull_id")) == "z002":
			title = "红尘劫"
		elif str(player.get("skull_id")) == "z003":
			title = "长夜明火"
		_entry(out, "form_buff", "buff", title, "化身之力短暂外放，全部伤害提高，并可施展觉醒技。", "%.1f 秒" % buff)
	var confidence := float(player.get("_z000_confidence_time"))
	if confidence > 0.0:
		_entry(out, "confidence", "buff", "淑女 · 自信", "技能冷却减半，全部伤害提高 1 点。", "%.1f 秒" % confidence)
	var stop_buff := float(player.get("_stop_buff_timer"))
	if stop_buff > 0.0:
		_entry(out, "stop_buff", "buff", "时停余势", "时停余韵，短时间内伤害提高。", "%.1f 秒" % stop_buff)
	var lifesteal := float(player.get("_lifesteal_buff"))
	if lifesteal > 0.0:
		_entry(out, "lifesteal", "buff", "血饮", "饮血之后，短时间内伤害提高。", "%.1f 秒" % lifesteal)
	var dash_attack := float(player.get("_dash_attack_window"))
	if dash_attack > 0.0:
		_entry(out, "dash_attack", "buff", "无影", "闪避后的下一记普攻附带额外伤害。", "%.1f 秒" % dash_attack)
	var guard := float(player.get("_hurt_guard_timer"))
	if guard > 0.0:
		_entry(out, "meditation", "buff", "禅定", "受击后凝神，短时间内减伤。", "%.1f 秒" % guard)
	if bool(Run.guard_available):
		_entry(out, "start_guard", "buff", "护砚", "本局首次受伤时自动减免。", "待触发")
	var buddha := int(Run.c013_buddha)
	if str(player.get("skull_id")) == "c013" and buddha > 0:
		_entry(out, "buddha", "buff", "佛陀", "每层全部伤害 +1，至多 3 层；满层后改为回血 1 点。", "%d／3 层" % buddha)

	var bleed := int(player.get("_bleed_stacks"))
	if bleed > 0:
		_entry(out, "bleed", "debuff", "流血", "每层持续扣血，新层刷新持续时间。", "%d 层 · %.1f 秒" % [bleed, float(player.get("_bleed_time"))], false)
	var cuts: Array = player.get("_cuts")
	if not cuts.is_empty():
		_entry(out, "cuts", "debuff", "割伤", "割伤会在各自时刻结算。", "%d 段" % cuts.size(), false)
	var burn := int(player.get("_mo_ting_burn_stacks"))
	if burn > 0:
		_entry(out, "burn", "debuff", "贯昼灼烧", "灼烧越深，墨霆的激光越痛。", "%d 层 · %.1f 秒" % [burn, float(player.get("_mo_ting_burn_time"))], false)
	var flame := int(player.get("_fen_ding_burn_stacks"))
	if flame > 0:
		_entry(out, "flame", "debuff", "焚鼎怒焰", "永久叠加，共用一个逐渐加速的灼烧计时。", "%d 层" % flame, false)
	var vulnerable := float(player.get("_ming_zhong_vulnerable_time"))
	if vulnerable > 0.0:
		_entry(out, "vulnerable", "debuff", "易伤", "受到伤害时额外多受 1 点。", "%.1f 秒" % vulnerable, false)
	var cripple := float(player.get("_cripple_time"))
	if cripple > 0.0:
		_entry(out, "cripple", "debuff", "致残", "暂时封住跳跃、闪避与位移技能。", "%.1f 秒" % cripple, false)
	var stun := float(player.get("_stun_time"))
	if stun > 0.0:
		_entry(out, "stun", "debuff", "眩晕", "无法操作。", "%.1f 秒" % stun, false)
	var seal := float(player.get("_passive_seal_time"))
	if seal > 0.0:
		_entry(out, "passive_seal", "debuff", "剥离", "被动与局内强化暂时失效。", "%.1f 秒" % seal, false)
	if bool(player.get("_sui_yue_pressure")):
		_entry(out, "pressure", "debuff", "邪佛压场", "外来增益被压制；基础形态、回血与觉醒不受影响。", "持续", false)
	if bool(player.get("wu_che_wanted")):
		_entry(out, "wanted", "debuff", "武车通缉", "武车召唤物伤害更高；闪避武撞可洗脱通缉。", "生效", false)


static func _add_passives(player, out: Array) -> void:
	for id in Meta.battle_passive_candidates(str(player.get("skull_id"))):
		var info: Dictionary = Meta.battle_passive_info(str(id))
		if info.is_empty():
			continue
		var active := bool(player.call("has_battle_passive", str(id)))
		_entry(out, str(id), "passive", str(info.get("name", id)), str(info.get("desc", "")), "" if active else "封印", active)


static func _add_stolen(out: Array) -> void:
	for packet in Run.z003_stolen.values():
		var type_id := str(packet.get("type_id", ""))
		var passives: Array = packet.get("passives", [])
		var formal = CodexText.ENEMY_PASSIVES.get(type_id, {})
		for i in passives.size():
			var id := str(passives[i])
			var info: Dictionary = Meta.battle_passive_info(id)
			if info.is_empty():
				if formal is Array and not formal.is_empty():
					info = formal[mini(i, formal.size() - 1)]
				elif formal is Dictionary:
					info = formal
			_entry(out, "stolen_" + id, "stolen", "夺取 · " + str(info.get("name", id)), str(info.get("desc", "血色切割夺取的被动。")), "已夺取")


static func _add_upgrades(out: Array) -> void:
	for key in Run.upgrades:
		var level := int(Run.upgrades[key])
		if level <= 0:
			continue
		var info: Dictionary = Run.card_info(str(key))
		_entry(out, "upgrade_" + str(key), "upgrade", str(info.get("label", key)), str(info.get("desc", "")), "%d 级" % level)


static func skill_name(player, index: int) -> String:
	var list: Array = CodexText.FORM_SKILL_TEXT.get(str(player.get("skull_id")), [])
	if index >= 0 and index < list.size():
		return str(list[index].get("name", "技能"))
	return "技能"


static func skill_cooldown(player, skill_id: String) -> float:
	var cds: Dictionary = player.get("_skill_cds")
	return maxf(0.0, float(cds.get(skill_id, 0.0)))


static func skill_lock(player, skill_id: String) -> String:
	var configs = player.get("skill_config")
	var cfg: Dictionary = configs.get(skill_id, {}) if configs is Dictionary else {}
	if cfg.is_empty():
		return "不可用"
	if bool(cfg.get("require_buff", false)) and float(player.get("_awaken_time")) <= 0.0 and float(player.get("_buff_timer")) <= 0.0:
		return "觉醒"
	if str(player.get("skull_id")) == "z002" and bool(cfg.get("once_per_awaken", false)) and bool(player.get("_pipa_o_used")):
		return "已用"
	if float(player.get("_cripple_time")) > 0.0 and bool(player.call("_skill_has_displacement", skill_id, cfg)):
		return "封锁"
	return ""
