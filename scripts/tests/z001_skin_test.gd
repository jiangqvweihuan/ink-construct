extends Node

## Z001 五套皮肤上架回归：定义 / 素材 / 动画 / 缩放、购买-穿戴-卸载、商店 UI 全链路。
## 只改内存状态：Meta.persist 关闭，不写玩家存档。

const Skins := preload("res://scripts/systems/skins.gd")
const Skulls := preload("res://scripts/player/skulls.gd")
const OWNER := "z001"

var _checks := 0
var _failed := 0


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("[ZS] ", ("PASS " if ok else "FAIL "), label)


func _ready() -> void:
	Run.balance_scaling = false
	Meta.persist = false
	Meta.skins = {}
	Meta.skin_worn = {}
	var base: Dictionary = Skulls.SKULLS[OWNER]
	var base_data = load(str(base["data"]))
	var base_h := float(base_data.call("get_height"))
	var base_names := _name_set(base_data)
	var base_dur := _dur_map(base_data)
	var required := _required_anims(base)
	var timed := _timed_anims(base)
	var defs: Array = Skins.defs(OWNER, false)
	_check(defs.size() == 5, "上架 5 套皮肤（实际 %d）" % defs.size())
	_check(str(Skins.group(OWNER, false).get("label", "")) == "烬生", "商店分类名为烬生")
	var base_pic := str(base.get("portrait", ""))
	_check(base_pic != "" and ResourceLoader.exists(base_pic), "基础形态原画已配置")

	# A. 定义与素材
	for raw in defs:
		var d: Dictionary = raw
		var sid := str(d.get("id", ""))
		_check(not sid.is_empty(), "皮肤 id 非空")
		_check(not str(d.get("name", "")).is_empty(), "%s 名称非空" % sid)
		_check(not str(d.get("desc", "")).is_empty(), "%s 描述非空" % sid)
		_check(not str(d.get("tag", "")).is_empty(), "%s 分类标签非空" % sid)
		_check(int(d.get("price", 0)) == 100, "%s 定价 100" % sid)
		var pic := str(d.get("portrait", ""))
		_check(pic != "" and ResourceLoader.exists(pic), "%s 展示图存在" % sid)
		var path := Skins.data_path(OWNER, sid, false)
		_check(ResourceLoader.exists(path), "%s 骨架文件存在" % sid)
		var ok := Skins.loadable(OWNER, sid, false)
		_check(ok, "%s 骨架可加载" % sid)
		if not ok:
			continue
		var data = load(path)
		var names := _name_set(data)
		var dur := _dur_map(data)
		var preview := str(d.get("preview", ""))
		_check(preview != "" and names.has(preview), "%s 预览动画可用: %s" % [sid, preview])
		var missing: Array = []
		for n in required:
			if not names.has(str(n)):
				missing.append(str(n))
		_check(missing.is_empty(), "%s 全部战斗动画齐全%s" % [sid, ("" if missing.is_empty() else "，缺 " + str(missing))])
		var drift: Array = []
		for n in timed:
			var key := str(n)
			if not dur.has(key):
				continue
			if absf(float(dur[key]) - float(base_dur.get(key, 0.0))) > 0.001:
				drift.append("%s %.3f→%.3f" % [key, float(base_dur.get(key, 0.0)), float(dur[key])])
		_check(drift.is_empty(), "%s 技能动画时长与基础形态一致%s" % [sid, ("" if drift.is_empty() else "，偏差 " + str(drift))])
		var want_scale := 0.48 * base_h / maxf(float(data.call("get_height")), 1.0)
		_check(absf(float(d.get("scale", 0.0)) - want_scale) < 0.003,
			"%s 缩放 %.3f 对齐体型（期望 %.3f）" % [sid, float(d.get("scale", 0.0)), want_scale])

	# B. 购买 / 重复购买 / 墨锭不足
	Meta.ink = 1000
	var bought_ids: Array = []
	for raw in defs:
		var d: Dictionary = raw
		var sid := str(d.get("id", ""))
		var price := Skins.price_of(d)
		var before := Meta.ink
		_check(Skins.buy(OWNER, sid, false), "%s 购买成功" % sid)
		_check(Meta.ink == before - price, "%s 扣款 %d" % [sid, price])
		_check(not Skins.buy(OWNER, sid, false), "%s 重复购买被拒绝" % sid)
		bought_ids.append(sid)
	Meta.skins.erase(Skins.key(OWNER, "zj5"))
	Meta.ink = 99
	_check(not Skins.buy(OWNER, "zj5", false) and Meta.ink == 99, "墨锭不足时不扣款")
	Meta.ink = 1000
	_check(Skins.buy(OWNER, "zj5", false), "补足墨锭后可再次购买")

	# C. 穿戴 / 卸载 → 形态表与运行时骨架
	var base_path := str(base["data"])
	for raw in defs:
		var d: Dictionary = raw
		var sid := str(d.get("id", ""))
		Skins.wear(OWNER, sid)
		var prof: Dictionary = Skulls.get_profile(OWNER)
		_check(str(prof["data"]) == Skins.data_path(OWNER, sid, false), "%s 穿戴后骨架切换" % sid)
		_check(absf(float(prof["scale"]) - float(d["scale"])) < 0.0001, "%s 穿戴后缩放生效" % sid)
		_check(str(prof["anim"]["idle"]) == "stand" and str(prof["anim"]["dead"]) == "dead",
			"%s 动画映射保持完整" % sid)
		_check(str(prof.get("portrait", "")) == str(d.get("portrait", "")), "%s 穿戴后原画切换" % sid)
	Skins.wear(OWNER, "zj5")
	var p = load("res://scenes/player/player.tscn").instantiate()
	p.skull_id = OWNER
	p.position = Vector2(400, 560)
	add_child(p)
	p.set_physics_process(false)
	_check(absf(p.base_scale - 0.422) < 0.0001, "运行时采用皮肤缩放")
	_check(str(p.sprite.get("skeleton_data_res").resource_path) == Skins.data_path(OWNER, "zj5", false),
		"运行时骨架为玄鸦素材")
	Skins.wear(OWNER, "zj1")
	p._apply_profile(OWNER)
	p._setup_spine()
	_check(absf(p.base_scale - 0.447) < 0.0001, "局内换装立即更新缩放")
	_check(str(p.sprite.get("skeleton_data_res").resource_path) == Skins.data_path(OWNER, "zj1", false),
		"局内换装立即更新骨架")
	Skins.wear(OWNER, "")
	var clean: Dictionary = Skulls.get_profile(OWNER)
	_check(str(clean["data"]) == base_path and absf(float(clean["scale"]) - 0.48) < 0.0001, "卸载恢复原装")

	# D. 商店 UI：列表 / 详情 / 购买 / 穿戴 / 卸载
	Meta.skins = {}
	Meta.skin_worn = {}
	Meta.ink = 1000
	var shop = load("res://scenes/ui/shop_panel.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	shop._tab = "appearance"
	shop._appearance_enemy = false
	shop._appearance_owner = OWNER
	shop._appearance_pick = "zj1"
	shop._refresh()
	await get_tree().process_frame
	var labels: Array = []
	_collect_labels(shop, labels)
	_check(_has_label(labels, "烬生"), "商店列表展示烬生分类")
	_check(_has_label(labels, "5 套"), "商店列表展示 5 套")
	_check(_has_label(labels, "烬白"), "商店列表展示烬白")
	_check(_has_label(labels, "烬白 · 墨羽"), "详情页展示名称与标签")
	_check(_has_label(labels, "银发披墨氅，赤刃挑余烬；焦土尽头独行的无名剑客。"), "详情页展示描述")
	_check(_has_label(labels, "购买 · 100 墨锭"), "未购买时展示购买按钮")
	shop._buy_pick()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(Meta.ink == 900 and Skins.owned(OWNER, "zj1"), "商店购买链路扣款并入库")
	labels.clear()
	_collect_labels(shop, labels)
	_check(_has_label(labels, "穿    戴"), "购买后按钮切换为穿戴")
	shop._wear_pick()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(Skins.worn(OWNER) == "zj1", "商店穿戴链路生效")
	labels.clear()
	_collect_labels(shop, labels)
	_check(_has_label(labels, "使 用 中"), "穿戴后按钮切换为使用中")
	_check(_has_label(labels, "5 套 · 烬白"), "分类行回显当前穿戴")
	shop._reset_skin()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(Skins.worn(OWNER) == "", "商店卸载链路生效")
	labels.clear()
	_collect_labels(shop, labels)
	_check(_has_label(labels, "穿    戴"), "卸载后按钮恢复为穿戴")
	Meta.ink = 0
	shop._appearance_pick = "zj2"
	shop._refresh()
	await get_tree().process_frame
	labels.clear()
	_collect_labels(shop, labels)
	_check(_has_label(labels, "墨锭不足 · 需 100"), "墨锭不足时按钮给出提示")
	shop.queue_free()
	await get_tree().process_frame

	Meta.skins = {}
	Meta.skin_worn = {}
	print("[ZS] DONE checks=%d failed=%d" % [_checks, _failed])
	get_tree().quit()


func _name_set(data) -> Dictionary:
	var out := {}
	for a in data.call("get_animations"):
		out[str(a.call("get_name"))] = true
	return out


func _dur_map(data) -> Dictionary:
	var out := {}
	for a in data.call("get_animations"):
		out[str(a.call("get_name"))] = float(a.call("get_duration"))
	return out


## 基础形态实际会播放的全部动画：待机/移动/受击链/闪避/跳跃/普攻/技能。
func _required_anims(p: Dictionary) -> Array:
	var out := {}
	var anim: Dictionary = p["anim"]
	for k in anim:
		out[str(anim[k])] = true
	for raw in p.get("attacks", []):
		var a: Dictionary = raw
		if a.has("anim"):
			out[str(a["anim"])] = true
		for n in a.get("pool", []):
			out[str(n)] = true
	for k in p.get("skills", {}):
		var cfg: Dictionary = p["skills"][k]
		if cfg.has("pool"):
			for n in cfg["pool"]:
				out[str(n)] = true
		elif cfg.has("anim"):
			out[str(cfg["anim"])] = true
		else:
			out[str(k)] = true
		var aw: Dictionary = cfg.get("awaken", {})
		if aw.has("anim"):
			out[str(aw["anim"])] = true
		for n in aw.get("pool", []):
			out[str(n)] = true
	for n in p.get("knock_chain", []):
		out[str(n)] = true
	var dp: Dictionary = p.get("dash_pool", {})
	for mv in dp.get("move", []):
		out[str(mv["anim"])] = true
	var still: Dictionary = dp.get("still", {})
	if still.has("anim"):
		out[str(still["anim"])] = true
	return out.keys()


## 时序敏感动画：普攻与技能（受击链按真实动画时长接续，不要求与基础形态同长）。
func _timed_anims(p: Dictionary) -> Array:
	var out := {}
	for raw in p.get("attacks", []):
		var a: Dictionary = raw
		if a.has("anim"):
			out[str(a["anim"])] = true
		for n in a.get("pool", []):
			out[str(n)] = true
	for k in p.get("skills", {}):
		var cfg: Dictionary = p["skills"][k]
		if cfg.has("pool"):
			for n in cfg["pool"]:
				out[str(n)] = true
		elif cfg.has("anim"):
			out[str(cfg["anim"])] = true
		else:
			out[str(k)] = true
		var aw: Dictionary = cfg.get("awaken", {})
		if aw.has("anim"):
			out[str(aw["anim"])] = true
	return out.keys()


func _collect_labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_collect_labels(c, out)


func _has_label(labels: Array, text: String) -> bool:
	for l in labels:
		if str(l) == text:
			return true
	return false
