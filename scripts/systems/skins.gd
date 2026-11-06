extends Node

## 外观收藏：皮肤登记表 + 购买 / 穿戴 / 覆盖。
##
## 皮肤只改视觉：data / scale / 动画名映射，不动数值与技能表。
## 玩家皮肤绑在化身上（skulls.gd 的 get_profile 统一套用）；
## 敌人皮肤绑在敌人类型上（enemy_types.gd / boss_types.gd 的取值函数统一套用）。
## 已购与穿戴记录存 Meta（meta.json），存档键：skins / skin_worn。

const PRICE := 100

const PLAYER := {
	"c013": {"label": "力僧", "skins": [
		{"id": "ds1", "name": "枯禅", "scale": 0.487},
		{"id": "ds2", "name": "镇岳", "scale": 0.460},
		{"id": "ds3", "name": "伏魔", "scale": 0.494},
	]},
	"c023": {"label": "梅剑", "skins": [
		{"id": "mj1", "name": "暗香", "scale": 0.474},
		{"id": "mj2", "name": "疏枝", "scale": 0.474},
	]},
	"z000": {"label": "剑仙", "skins": [
		{"id": "jx1", "name": "霜翎", "scale": 0.431, "anim": {"skill02-": "skill02"}},
		{"id": "jx2", "name": "照雪", "scale": 0.431, "anim": {"skill02-": "skill02"}},
		{"id": "jx3", "name": "裂云", "scale": 0.414, "anim": {"skill02-": "skill02"}},
		{"id": "jx4", "name": "长歌", "scale": 0.436, "anim": {"skill02-": "skill02"}},
		{"id": "jx5", "name": "归鹤", "scale": 0.436, "anim": {"skill02-": "skill02"}},
	]},
	"z002": {"label": "绛弦", "skins": [
		{"id": "syy1", "name": "低眉", "scale": 0.406,
			"anim": {"run4": "run", "run-": "dash02_front", "skill13_02-cankao": "skill13_02", "skill16_02-": "skill16_02", "atked_fall_end-": "atked_fall_end"},
			"skill_anims": {"skill13-": "skill13_02"}},
		{"id": "syy2", "name": "拨云", "scale": 0.420,
			"anim": {"skill16_02-": "skill16_02"}},
		{"id": "syy3", "name": "余音", "scale": 0.401,
			"anim": {"run4": "run", "run-": "dash02_front", "skill13_02-cankao": "skill13_02", "skill16_02-": "skill16_02", "atked_fall_end-": "atked_fall_end"},
			"skill_anims": {"skill13-": "skill13_02"}},
	]},
	"z003": {"label": "影殇", "skins": [
		{"id": "jqwh1", "name": "无归", "scale": 0.431, "anim": {"skill17_02-": "skill17_02-cankao"}},
		{"id": "jqwh2", "name": "断魂", "scale": 0.431},
		{"id": "jqwh3", "name": "夜行", "scale": 0.431, "anim": {"skill17_02-": "skill17_02-cankao"}},
	]},
}

const ENEMY := {
	"c009": {"label": "墨霆", "skins": [
		{"id": "mt1", "name": "墨鳞", "scale": 0.550},
	]},
	"c015a1": {"label": "焚鼎", "skins": [
		{"id": "fd1", "name": "余烬", "scale": 0.550,
			"anim": {"skill03-01": "skill03", "skill03-02": "skill04", "skill3": "skill03", "skill4": "skill04"}},
		{"id": "fd2", "name": "朱焰", "scale": 0.550,
			"anim": {"skill03-01": "skill03", "skill03-02": "skill04", "skill3": "skill03", "skill4": "skill04"}},
		{"id": "fd3", "name": "焦土", "scale": 0.550,
			"anim": {"skill03-01": "skill03", "skill03-02": "skill04", "skill3": "skill03", "skill4": "skill04"}},
	]},
	"c016": {"label": "刀客", "skins": [
		{"id": "sm1", "name": "白刃", "scale": 0.320},
		{"id": "sm2", "name": "断水", "scale": 0.320},
	]},
	"c017": {"label": "蛮兵", "skins": [
		{"id": "mb1", "name": "山骨", "scale": 0.252,
			"anim": {"walk2": "run", "skill03_1": "skill03", "skill03_2": "skill02", "skill03_3": "skill01"}},
		{"id": "mb2", "name": "蛮甲", "scale": 0.256,
			"anim": {"walk2": "run", "skill03_1": "skill03", "skill03_2": "skill02", "skill03_3": "skill01"}},
	]},
	"c012": {"label": "青笠剑客", "skins": [
		{"id": "ql1", "name": "青笠", "scale": 0.563},
		{"id": "ql2", "name": "听雨", "scale": 0.563},
		{"id": "ql3", "name": "问剑", "scale": 0.563},
	]},
}


static var _loadable_cache := {}


## 皮肤骨架是否真的可用（3.6 旧文件在 4.2 运行时里会加载失败，不能穿、不能卖）
static func loadable(owner_id: String, skin_id: String, is_enemy: bool) -> bool:
	var path := data_path(owner_id, skin_id, is_enemy)
	if _loadable_cache.has(path):
		return bool(_loadable_cache[path])
	var ok := false
	if ResourceLoader.exists(path):
		var data = load(path)
		ok = data != null and bool(data.call("is_skeleton_data_loaded"))
	_loadable_cache[path] = ok
	return ok


static func owners(is_enemy: bool) -> Array:
	return ENEMY.keys() if is_enemy else PLAYER.keys()


static func group(owner_id: String, is_enemy: bool) -> Dictionary:
	return (ENEMY if is_enemy else PLAYER).get(owner_id, {})


static func defs(owner_id: String, is_enemy: bool) -> Array:
	return group(owner_id, is_enemy).get("skins", [])


static func find(owner_id: String, skin_id: String, is_enemy: bool) -> Dictionary:
	if skin_id == "":
		return {}
	for d in defs(owner_id, is_enemy):
		if str(d["id"]) == skin_id:
			return d
	return {}


static func key(owner_id: String, skin_id: String) -> String:
	return "%s/%s" % [owner_id, skin_id]


static func data_path(owner_id: String, skin_id: String, is_enemy: bool) -> String:
	var dir := "enemies" if is_enemy else "player"
	return "res://art/characters/%s/skins/%s/%s/%s_data.tres" % [dir, owner_id, skin_id, skin_id]


static func owned(owner_id: String, skin_id: String) -> bool:
	return Meta.owns_skin(key(owner_id, skin_id))


static func worn(owner_id: String) -> String:
	return Meta.worn_skin(owner_id)


static func buy(owner_id: String, skin_id: String, is_enemy: bool) -> bool:
	if find(owner_id, skin_id, is_enemy).is_empty():
		return false
	if not loadable(owner_id, skin_id, is_enemy):
		return false
	return Meta.buy_skin(key(owner_id, skin_id), PRICE)


static func wear(owner_id: String, skin_id: String) -> void:
	Meta.wear_skin(owner_id, skin_id)


## 把穿戴的玩家皮肤套到形态表上：只换 data / scale / 动画名，数值与技能表原样保留。
static func player_profile(owner_id: String, base: Dictionary) -> Dictionary:
	var sid := Meta.worn_skin(owner_id)
	if sid == "":
		return base
	var d: Dictionary = find(owner_id, sid, false)
	if d.is_empty() or not loadable(owner_id, sid, false):
		return base
	var p: Dictionary = base.duplicate(true)
	p["data"] = data_path(owner_id, sid, false)
	p["scale"] = float(d.get("scale", base["scale"]))
	var amap: Dictionary = d.get("anim", {})
	if not amap.is_empty():
		_remap_profile(p, amap)
	var smap: Dictionary = d.get("skill_anims", {})
	for k in smap:
		var cfg: Dictionary = p.get("skills", {}).get(k, {})
		if not cfg.is_empty() and not cfg.has("pool"):
			cfg["anim"] = str(smap[k])
	return p


## 敌人皮肤：在类型表副本上换 data / scale，并深度替换动画名（值 + 字典键）。
static func enemy_profile(owner_id: String, base: Dictionary) -> Dictionary:
	var sid := Meta.worn_skin(owner_id)
	if sid == "":
		return base
	var d: Dictionary = find(owner_id, sid, true)
	if d.is_empty() or not loadable(owner_id, sid, true):
		return base
	var t: Dictionary = base.duplicate(true)
	t["data"] = data_path(owner_id, sid, true)
	t["scale"] = float(d.get("scale", base.get("scale", 0.4)))
	t["skin_id"] = sid
	var amap: Dictionary = d.get("anim", {})
	if not amap.is_empty():
		t = _deep_remap(t, amap)
	return t


static func _remap_profile(p: Dictionary, map: Dictionary) -> void:
	var anim: Dictionary = p.get("anim", {})
	for k in anim:
		anim[k] = _n(str(anim[k]), map)
	var chain: Array = p.get("knock_chain", [])
	for i in chain.size():
		chain[i] = _n(str(chain[i]), map)
	var vic: Array = p.get("victory", [])
	for i in vic.size():
		vic[i] = _n(str(vic[i]), map)
	for atk in p.get("attacks", []):
		if atk.has("anim"):
			atk["anim"] = _n(str(atk["anim"]), map)
		var pool: Array = atk.get("pool", [])
		for i in pool.size():
			pool[i] = _n(str(pool[i]), map)
		if atk.has("hit_at"):
			atk["hit_at"] = _remap_keys(atk["hit_at"], map)
		if atk.has("pool") and atk.has("range"):
			atk["range"] = _remap_keys(atk["range"], map)
	var dp: Dictionary = p.get("dash_pool", {})
	if not dp.is_empty():
		var still: Dictionary = dp.get("still", {})
		if still.has("anim"):
			still["anim"] = _n(str(still["anim"]), map)
		for mv in dp.get("move", []):
			if mv.has("anim"):
				mv["anim"] = _n(str(mv["anim"]), map)
	for k in p.get("skills", {}):
		var cfg: Dictionary = p["skills"][k]
		var pool: Array = cfg.get("pool", [])
		for i in pool.size():
			pool[i] = _n(str(pool[i]), map)
		if cfg.has("hit_at"):
			cfg["hit_at"] = _remap_keys(cfg["hit_at"], map)
		if cfg.has("pool") and cfg.has("range"):
			cfg["range"] = _remap_keys(cfg["range"], map)
		var aw: Dictionary = cfg.get("awaken", {})
		if aw.has("anim"):
			aw["anim"] = _n(str(aw["anim"]), map)


static func _remap_keys(d: Dictionary, map: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[_n(str(k), map)] = d[k]
	return out


static func _deep_remap(v, map: Dictionary):
	if v is Dictionary:
		var out := {}
		for k in v:
			out[_n(str(k), map)] = _deep_remap(v[k], map)
		return out
	if v is Array:
		var arr: Array = []
		for x in v:
			arr.append(_deep_remap(x, map))
		return arr
	if v is String:
		return _n(v, map)
	return v


static func _n(name: String, map: Dictionary) -> String:
	return str(map.get(name, name))
