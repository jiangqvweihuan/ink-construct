extends RefCounted

## 斗蛐蛐可选名录：可玩化身 + 全部杂兵 + 全部首领，统一成战斗单位能直接吃的一套字段。
## 原表一行不改：化身读 Skulls.SKULLS，杂兵读 EnemyTypes.TYPES，首领读 BossTypes.BOSSES。
## 两套招式写法在这里抹平：化身是 attacks 表（hits/damage/range 同层），
## 敌人是 attacks 名单 + hit_at/ranges/damage 三张并行表，统一产出
## {anim, at, lock, damage, range} 的 move。

const Skulls := preload("res://scripts/player/skulls.gd")
const EnemyTypes := preload("res://scripts/enemies/enemy_types.gd")
const BossTypes := preload("res://scripts/enemies/boss_types.gd")

const ENEMY_ORDER := ["c016", "c017", "c035", "c037", "c018", "c012"]
const BOSS_ORDER := ["c009", "c015a1", "c001", "c008", "c032"]


static func entries() -> Array:
	var list: Array = []
	for id in Skulls.ORDER:
		list.append(_skull(str(id)))
	for id in ENEMY_ORDER:
		list.append(_enemy(str(id), "杂兵"))
	for id in BOSS_ORDER:
		list.append(_enemy(str(id), "首领"))
	return list


static func find(id: String) -> Dictionary:
	for e in entries():
		if str(e["id"]) == id:
			return e
	return entries()[0]


static func _skull(id: String) -> Dictionary:
	var info: Dictionary = Skulls.SKULLS.get(id, {})
	var a: Dictionary = info.get("anim", {})
	var moves: Array = []
	for atk in info.get("attacks", []):
		var m := _skull_move(atk)
		if not m.is_empty():
			moves.append(m)
	if moves.is_empty():
		moves.append({"anim": str(a.get("idle", "stand")), "at": 0.5, "lock": 1.0,
			"damage": 1, "range": 120.0})
	# 技能招也接进来当重招用：只留有明确距离判定的，带弹道/闪现/根位移的跳过（观战没有那套机制）
	var skills: Dictionary = info.get("skills", {})
	for key in skills:
		var sh: Array = skills[key].get("hits", [])
		if sh.is_empty():
			continue
		var ok := true
		var at2 := 0.0
		var rng2 := 0.0
		var total2 := 0
		for h in sh:
			if not (h is Dictionary) or not h.has("range"):
				ok = false
				break
			at2 = maxf(at2, float(h.get("at", 0.3)))
			rng2 = maxf(rng2, float(h["range"]))
			total2 += int(h.get("damage", 1))
		if not ok or at2 > 2.8:
			continue
		moves.append({
			"anim": str(key), "at": at2, "lock": minf(at2 + 0.5, 3.2),
			"damage": clampi(int(round(float(total2) * 0.6)), 1, 4), "range": rng2,
		})
	return {
		"id": id, "kind": "化身",
		"name": str(info.get("name", id)), "tag": str(info.get("label", "")),
		"data": str(info.get("data", "")), "portrait": str(info.get("portrait", "")),
		"scale": float(info.get("scale", 1.0)), "radius": float(info.get("body_radius", 30.0)),
		"anim": {
			"idle": str(a.get("idle", "stand")),
			"run": str(a.get("run", "run")),
			"hurt": str(a.get("hurt", "atked")),
			"dead": str(a.get("dead", "dead")),
		},
		"moves": moves,
	}


## 化身招式：hits 有两种写法——早期只写到点时刻（float），后期写成带伤害/距离的字典。
## 统一取最后一段的落点时刻与判定距离，多段伤害求和成一次出手的总伤害。
static func _skull_move(atk: Dictionary) -> Dictionary:
	var hits: Array = atk.get("hits", [])
	if not hits.is_empty():
		var total := 0
		var at := 0.3
		var rng := float(atk.get("range", 110.0))
		for h in hits:
			if h is Dictionary:
				total += int(h.get("damage", atk.get("damage", 1)))
				rng = float(h.get("range", rng))
				at = float(h.get("at", at))
			else:
				total += int(atk.get("damage", 1))
				at = float(h)
		return {
			"anim": str(atk.get("anim", "atk01")),
			"at": at,
			"lock": maxf(float(atk.get("lock", 0.7)), 0.3),
			"damage": maxi(1, total),
			"range": rng,
		}
	# 池式招式（影殇这类三段连击）：动画从 pool 里抽，时刻与距离按动画名分开标定
	var pool: Array = atk.get("pool", [])
	if pool.is_empty():
		return {}
	var anim := str(pool[randi() % pool.size()])
	var at_map = atk.get("hit_at", {})
	var rng_map = atk.get("range", {})
	var at2 := float(at_map[anim]) if at_map is Dictionary and at_map.has(anim) else 0.4
	var rng2 := 120.0
	if rng_map is Dictionary:
		rng2 = float(rng_map.get(anim, 120.0))
	elif rng_map is float or rng_map is int:
		rng2 = float(rng_map)
	return {
		"anim": anim,
		"at": at2,
		"lock": at2 + 0.3,
		"damage": maxi(1, int(atk.get("damage", 1))),
		"range": rng2,
	}


static func _enemy(id: String, kind: String) -> Dictionary:
	var t: Dictionary = EnemyTypes.TYPES.get(id, {}) if kind == "杂兵" else BossTypes.BOSSES.get(id, {})
	var a: Dictionary = t.get("anim", {})
	var attacks: Array = t.get("attacks", [])
	if attacks.is_empty():
		var stages: Array = t.get("stages", [])
		if not stages.is_empty():
			attacks = stages[0].get("attacks", [])
	var move_anims: Dictionary = t.get("move_anims", {})
	var hit_at: Dictionary = t.get("hit_at", {})
	var ranges: Dictionary = t.get("ranges", {})
	var damage: Dictionary = t.get("damage", {})
	var moves: Array = []
	for raw in attacks:
		var key := str(raw)
		if key.begins_with("transform"):
			continue # 变身招在观战里会换肤，跳过
		var times := _times(hit_at.get(key, 0.6))
		if times.is_empty():
			continue
		var last := times.size() - 1
		var at := maxf(float(times[last]), 0.3)
		var rng := _at(ranges.get(key, 0.0), last)
		if rng <= 1.0:
			rng = 150.0 # 武车这类判定写在脚本里的单位，给个近身兜底距离
		moves.append({
			"anim": str(move_anims.get(key, key)),
			"at": at,
			"lock": at + 0.3,
			"damage": maxi(1, int(round(_sum(damage.get(key, 1), times.size())))),
			"range": rng,
		})
	if moves.is_empty():
		moves.append({"anim": str(a.get("idle", "stand")), "at": 0.5, "lock": 1.0,
			"damage": 1, "range": 150.0})
	return {
		"id": id, "kind": kind,
		"name": str(t.get("label", id)), "tag": "",
		"data": str(t.get("data", "")), "portrait": str(t.get("portrait", "")),
		"scale": float(t.get("scale", 1.0)), "radius": float(t.get("body_radius", 30.0)),
		"anim": {
			"idle": str(a.get("idle", "stand")),
			"run": str(a.get("chase", a.get("patrol", a.get("idle", "run")))),
			"hurt": str(a.get("hurt", "atked")),
			"dead": str(a.get("dead", "atked_fall_end")),
		},
		"moves": moves,
	}


## hit_at 一项既可能是单次时刻，也可能是多段时刻数组
static func _times(v) -> Array:
	if v is Array:
		return v
	return [float(v)]


## ranges / damage 同理：数组按段取值，标量所有段共用
static func _at(v, idx: int) -> float:
	if v is Array:
		if v.is_empty():
			return 0.0
		return float(v[clampi(idx, 0, v.size() - 1)])
	return float(v)


## 一次出手的总伤害：多段伤害求和，标量按段数乘
static func _sum(v, hits: int) -> float:
	if v is Array:
		var total := 0.0
		for x in v:
			total += float(x)
		return total
	return float(v) * maxi(hits, 1)
