extends Node2D

## 攻击一致性审计探针（可 headless 运行）
## 目的：把「视觉范围 / 实际伤害判定范围 / 伤害触发时刻」三者逐条对齐，输出可核对的清单。
##   静态：配置完整性——hit_at 必须在动画真实时长内、ranges 与多段 hit_at 一一对应、
##         键名必须与运行时 _hit_key（move_pool 取演出动画名，其余取逻辑招名）一致。
##   动态：把假目标放在 range+body_radius 的边界内外、hit_height 的上下边界、身后两侧，
##         直接调 _deal_hit(seg)，验证实际判定边界与配置射程完全一致。
##   时序：真实执行 _attack_tick 的倒计时，记录每段命中弹出的动画时刻，与配置 hit_at 比对。
## 输出：[AUDIT] 行 + AUDIT RESULT checks=N fail=N

const Skulls := preload("res://scripts/player/skulls.gd")
const Types := preload("res://scripts/enemies/enemy_types.gd")
const BossTypes := preload("res://scripts/enemies/boss_types.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const EnemyScene := preload("res://scenes/enemies/c016.tscn")
const BossScene := preload("res://scenes/enemies/bosses/boss.tscn")

const FRAME := 1.0 / 60.0

var _checks := 0
var _fails := 0
var _log: FileAccess


## 敌方判定的假目标：只需要 body_radius / hp / hurt 三个接口
class FakeTarget extends Node2D:
	var hp := 9999
	var body_radius := 30.0
	var facing := -1

	func hurt(amount: int, _kb: Vector2, _src, _move) -> void:
		hp -= amount

	func take_damage(amount: int, _src) -> void:
		hp -= amount


func p(msg: String) -> void:
	print("[AUDIT] ", msg)
	if _log != null:
		_log.store_line("[AUDIT] " + msg)
		_log.flush()


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		p("FAIL " + msg)


func _ready() -> void:
	_log = FileAccess.open("res://tests/audit.log", FileAccess.WRITE)
	get_window().size = Vector2i(1280, 720)
	_audit_players_static()
	_audit_enemies_static()
	await _audit_enemies_dynamic()
	await _audit_player_hits_dynamic()
	p("AUDIT RESULT checks=%d fail=%d" % [_checks, _fails])
	if _log != null:
		_log.store_line("AUDIT RESULT checks=%d fail=%d" % [_checks, _fails])
		_log.flush()
	get_tree().quit()


# ---------------------------------------------------------------- 工具

func _anim_dur(data, name: String) -> float:
	if data == null or name.is_empty():
		return -1.0
	var a = data.call("find_animation", name)
	if a == null:
		return -1.0
	return float(a.call("get_duration"))


func _as_arr(v) -> Array:
	return v if v is Array else [v]


func _seg_range(v, seg: int, fallback: float) -> float:
	if v == null:
		return fallback
	if v is Array:
		var arr := v as Array
		return float(arr[mini(seg, arr.size() - 1)]) if not arr.is_empty() else fallback
	return float(v)


# ---------------------------------------------------------------- 玩家静态

func _audit_players_static() -> void:
	for id in Skulls.SKULLS.keys():
		var s: Dictionary = Skulls.SKULLS[str(id)]
		var data = load(str(s.get("data", "")))
		if data == null:
			p("INFO P/%s 骨架数据缺失，跳过" % str(id))
			continue
		var attacks: Array = s.get("attacks", [])
		for ai in attacks.size():
			_audit_player_attack(str(id), ai, attacks[ai], data)
		var skills: Dictionary = s.get("skills", {})
		for key in skills:
			_audit_player_skill(str(id), str(key), skills[key], data)
		for k in s.get("hud_skills", []):
			_ok(skills.has(str(k)), "P/%s HUD 技能不存在 %s" % [str(id), str(k)])


func _audit_player_attack(id: String, ai: int, atk: Dictionary, data) -> void:
	var tag := "P/%s/atk%d" % [id, ai + 1]
	if atk.has("pool") and not (atk["pool"] as Array).is_empty():
		var hit_map: Dictionary = atk.get("hit_at", {})
		var range_map: Dictionary = atk.get("range", {})
		for an in atk["pool"]:
			var anim := str(an)
			var dur := _anim_dur(data, anim)
			_ok(dur > 0.0, "%s 随机池动画缺失 %s" % [tag, anim])
			_ok(hit_map.has(anim), "%s 缺 hit_at[%s]" % [tag, anim])
			_ok(range_map.has(anim), "%s 缺 range[%s]" % [tag, anim])
			if hit_map.has(anim):
				_ok(float(hit_map[anim]) < dur + 0.001,
					"%s %s hit_at=%.3f 超出动画时长 %.3f" % [tag, anim, float(hit_map[anim]), dur])
			if range_map.has(anim):
				_ok(float(range_map[anim]) > 0.0, "%s %s range 非正" % [tag, anim])
		return

	var anim := str(atk.get("anim", ""))
	var dur := _anim_dur(data, anim)
	_ok(dur > 0.0, "%s 动画缺失 %s" % [tag, anim])
	var lock := float(atk.get("lock", dur))
	var hits: Array = atk.get("hits", [])
	_ok(not hits.is_empty(), "%s 没有 hits" % tag)
	for hi in hits.size():
		var h = hits[hi]
		if h is Dictionary and (h as Dictionary).has("projectile"):
			p("INFO %s 第%d段为投射物，近战射程不适用（由 projectile.gd 判定）" % [tag, hi + 1])
			continue
		var at := float((h as Dictionary).get("at", 0.0)) if h is Dictionary else float(h)
		var rng := float((h as Dictionary).get("range", atk.get("range", -1.0))) if h is Dictionary else float(atk.get("range", -1.0))
		_ok(at < dur + 0.001, "%s 第%d段 hit_at=%.3f 超出动画时长 %.3f" % [tag, hi + 1, at, dur])
		_ok(at < lock + 0.001, "%s 第%d段 hit_at=%.3f 在 lock %.3f 之后（永不触发）" % [tag, hi + 1, at, lock])
		_ok(rng > 0.0, "%s 第%d段 range 缺失/非正" % [tag, hi + 1])
	if absf(lock - dur) > 0.05:
		p("INFO %s lock=%.3f 动画时长=%.3f 差=%+.3f（画面收招后仍在攻击锁定）" % [tag, lock, dur, lock - dur])


func _audit_player_skill(id: String, key: String, cfg: Dictionary, data) -> void:
	var tag := "P/%s/skill:%s" % [id, key]
	var anims: Array = cfg.get("pool", [cfg.get("anim", key)])
	var dur := 0.0
	for an in anims:
		var d := _anim_dur(data, str(an))
		_ok(d > 0.0, "%s 技能动画缺失 %s" % [tag, str(an)])
		dur = maxf(dur, d)
	var hits: Array = cfg.get("hits", [])
	for hi in hits.size():
		var h: Dictionary = hits[hi]
		if h.has("at"):
			_ok(float(h["at"]) < dur + 0.001,
				"%s 第%d段 at=%.3f 超出动画时长 %.3f" % [tag, hi + 1, float(h["at"]), dur])
		if h.has("range"):
			_ok(float(h["range"]) > 0.0, "%s 第%d段 range 非正" % [tag, hi + 1])
	var tick: Dictionary = cfg.get("tick", {})
	if not tick.is_empty():
		var a := float(tick.get("from", 0.0))
		var b := float(tick.get("to", 0.0))
		_ok(a <= dur + 0.001 and b <= dur + 0.001, "%s tick %.2f~%.2f 超出动画时长 %.2f" % [tag, a, b, dur])
	if cfg.has("speed"):
		_ok(float(cfg["speed"]) > 0.0, "%s speed 非正" % tag)


# ---------------------------------------------------------------- 敌人静态

func _audit_enemies_static() -> void:
	for id in Types.TYPES.keys():
		_audit_enemy_cfg("E/" + str(id), Types.TYPES[str(id)], false)
	for id in BossTypes.BOSSES.keys():
		_audit_enemy_cfg("B/" + str(id), BossTypes.BOSSES[str(id)], true)


func _enemy_moves(t: Dictionary, is_boss: bool) -> Array:
	var moves: Array = []
	if is_boss:
		for stage in t.get("stages", []):
			for m in stage.get("attacks", []):
				if not moves.has(str(m)):
					moves.append(str(m))
	else:
		for m in t.get("attacks", []):
			if not moves.has(str(m)):
				moves.append(str(m))
	var limit: Dictionary = t.get("limit", {})
	var lm := str(limit.get("move", ""))
	if not lm.is_empty() and not moves.has(lm):
		moves.append(lm)
	return moves


func _audit_enemy_cfg(tag: String, t: Dictionary, is_boss: bool) -> void:
	var data = load(str(t.get("data", "")))
	if data == null:
		p("INFO %s 骨架数据缺失，跳过静态" % tag)
		return
	var ranges: Dictionary = t.get("ranges", {})
	var hit_at: Dictionary = t.get("hit_at", {})
	var pool: Dictionary = t.get("move_pool", {})
	var move_anims: Dictionary = t.get("move_anims", {})
	for move in _enemy_moves(t, is_boss):
		if pool.has(move) and not (pool[move] as Array).is_empty():
			for v in pool[move]:
				_check_enemy_move("%s/%s" % [tag, move], str(v), str(v), hit_at, ranges, data)
		else:
			_check_enemy_move("%s/%s" % [tag, move], move, str(move_anims.get(move, move)), hit_at, ranges, data)


func _check_enemy_move(tag: String, key: String, visual: String, hit_at: Dictionary, ranges: Dictionary, data) -> void:
	if hit_at.has(key) and hit_at[key] is Array and (hit_at[key] as Array).is_empty():
		p("INFO %s 无命中段（非伤害技/占位），跳过" % tag)
		return
	var dur := _anim_dur(data, visual)
	_ok(dur > 0.0, "%s 动画缺失 %s" % [tag, visual])
	_ok(hit_at.has(key), "%s 缺 hit_at[%s]（运行时取查表键 %s）" % [tag, key, key])
	_ok(ranges.has(key), "%s 缺 ranges[%s]" % [tag, key])
	if not hit_at.has(key) or not ranges.has(key):
		return
	var ha: Array = _as_arr(hit_at[key])
	var ra: Array = _as_arr(ranges[key])
	if ra.size() < ha.size():
		p("INFO %s ranges 段数 %d < hit_at 段数 %d（后段会静默复用末值）" % [tag, ra.size(), ha.size()])
	for i in ha.size():
		_ok(float(ha[i]) < dur + 0.001,
			"%s 第%d段 hit_at=%.3f 超出 %s 时长 %.3f" % [tag, i + 1, float(ha[i]), visual, dur])
	for v in ra:
		_ok(float(v) >= 0.0, "%s ranges 存在负值" % tag)
		if float(v) == 0.0:
			p("INFO %s ranges 有 0（自增益/占位招式）" % tag)


# ---------------------------------------------------------------- 敌人动态

func _audit_enemies_dynamic() -> void:
	for id in Types.TYPES.keys():
		await _dynamic_enemy("E/" + str(id), Types.TYPES[str(id)], false)
	for id in BossTypes.BOSSES.keys():
		await _dynamic_enemy("B/" + str(id), BossTypes.BOSSES[str(id)], true)


func _dynamic_enemy(tag: String, t: Dictionary, is_boss: bool) -> void:
	var node: Node2D = BossScene.instantiate() if is_boss else EnemyScene.instantiate()
	node.set("type_id", str(tag.split("/")[1]))
	add_child(node)
	await get_tree().physics_frame
	await get_tree().physics_frame
	node.set_physics_process(false)
	var fake := FakeTarget.new()
	fake.add_to_group("player")
	add_child(fake)
	node.set("_target", fake)
	var base: Vector2 = node.global_position
	node.set("facing", 1)
	var hit_at: Dictionary = t.get("hit_at", {})
	var ranges: Dictionary = t.get("ranges", {})
	var pool: Dictionary = t.get("move_pool", {})
	var move_anims: Dictionary = t.get("move_anims", {})
	var both_map: Dictionary = node.get("_both_anims")
	var fallback := float(node.get("attack_range"))
	var height := float(node.get("attack_hit_height"))
	for move in _enemy_moves(t, is_boss):
		var variants: Array = []
		if pool.has(move) and not (pool[move] as Array).is_empty():
			for v in pool[move]:
				variants.append([str(v), str(v)])
		else:
			variants.append([move, str(move_anims.get(move, move))])
		var timed := false
		for pair in variants:
			var key := str(pair[0])
			var visual := str(pair[1])
			var ha: Array = _as_arr(hit_at.get(key, [0.9]))
			node.global_position = base
			node.velocity = Vector2.ZERO
			node.set("_attack_move", move)
			node.set("_attack_visual", visual)
			for seg in ha.size():
				var rng := _seg_range(ranges.get(key), seg, fallback)
				if rng <= 0.0:
					continue
				var seg_tag := "%s/%s seg%d" % [tag, key, seg + 1]
				_expect_enemy_landed(node, fake, base, rng, height, seg, bool(both_map.get(move, false)), seg_tag)
			# 时序：每招只真跑一次（同一套倒计时逻辑，按第一个演出动画校验）
			if not timed:
				timed = true
				_check_enemy_timing(node, fake, base, move, "%s/%s" % [tag, key])
	node.queue_free()
	fake.queue_free()
	await get_tree().process_frame


func _expect_enemy_landed(node, fake, base: Vector2, rng: float, height: float, seg: int, both: bool, tag: String) -> void:
	var radius := float(fake.body_radius)
	_expect_enemy_at(node, fake, base + Vector2(rng + radius - 0.5, 0.0), seg, true, tag + " 正前边界")
	_expect_enemy_at(node, fake, base + Vector2(rng + radius + 1.5, 0.0), seg, false, tag + " 正前越界")
	_expect_enemy_at(node, fake, base + Vector2(maxf(rng * 0.5, 1.0), -(height - 1.0)), seg, true, tag + " 纵向内")
	_expect_enemy_at(node, fake, base + Vector2(maxf(rng * 0.5, 1.0), -(height + 1.5)), seg, false, tag + " 纵向外")
	_expect_enemy_at(node, fake, base + Vector2(-(rng + radius - 0.5), 0.0), seg, both, tag + " 身后")


func _expect_enemy_at(node, fake, pos: Vector2, seg: int, expect: bool, tag: String) -> void:
	fake.global_position = pos
	fake.hp = 9999
	node.set("_attack_hit_landed", false)
	node.call("_deal_hit", seg)
	var got := bool(node.get("_attack_hit_landed"))
	_ok(got == expect, "%s 期望%s 实际%s (dx=%.1f dy=%.1f)" % [
		tag, "命中" if expect else "落空", "命中" if got else "落空",
		pos.x - node.global_position.x, pos.y - node.global_position.y])


func _check_enemy_timing(node, fake, base: Vector2, move: String, tag: String) -> void:
	fake.global_position = base + Vector2(2000.0, 0.0) # 打空：只观察命中段弹出时刻
	node.set("_target", fake)
	node.call("_start_attack", move, false)
	node.call("_release_token")
	var dur := float(node.get("_attack_dur"))
	var left: Array = (node.get("_attack_hits_left") as Array).duplicate()
	if left.is_empty():
		p("INFO %s 无命中段，跳过时序" % tag)
		return
	var expected: Array = []
	for e in left:
		expected.append(dur - float(e["t"]))
	var elapsed := 0.0
	var pops: Array = []
	var guard := 0
	while not (node.get("_attack_hits_left") as Array).is_empty() and elapsed < dur + 0.25 and guard < 3000:
		var before: int = (node.get("_attack_hits_left") as Array).size()
		elapsed += FRAME
		node.call("_attack_tick", FRAME)
		var after: int = (node.get("_attack_hits_left") as Array).size()
		for k in before - after:
			pops.append(elapsed)
		guard += 1
	_ok(pops.size() == expected.size(), "%s 命中段触发数 %d != 配置 %d" % [tag, pops.size(), expected.size()])
	for i in mini(pops.size(), expected.size()):
		_ok(absf(float(pops[i]) - float(expected[i])) <= FRAME + 0.002,
			"%s 第%d段 触发 %.3f != 动画时刻 %.3f" % [tag, i + 1, float(pops[i]), float(expected[i])])


# ---------------------------------------------------------------- 玩家动态

func _audit_player_hits_dynamic() -> void:
	var player = PlayerScene.instantiate()
	player.position = Vector2(640, 560)
	add_child(player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.set_physics_process(false)

	var bag = EnemyScene.instantiate()
	bag.set("type_id", "c016")
	bag.position = Vector2(900, 560)
	add_child(bag)
	await get_tree().physics_frame
	bag.set_physics_process(false)
	bag.max_hp = 999999

	for id in Skulls.SKULLS.keys():
		player.swap_skull(str(id))
		await get_tree().process_frame
		player.set_physics_process(false)
		player.facing = 1
		var base: Vector2 = player.global_position
		var attacks: Array = player.attacks
		for ai in attacks.size():
			var atk: Dictionary = attacks[ai]
			if atk.has("pool"):
				continue # 随机池普攻各有独立 hit_at/range 表，静态已逐动画校验
			var hits: Array = atk.get("hits", [])
			for hi in hits.size():
				var h = hits[hi]
				if h is Dictionary and (h as Dictionary).has("projectile"):
					continue # 投射物伤害由 projectile.gd 结算，不走普攻近战判定
				var rng := float((h as Dictionary).get("range", atk.get("range", 0.0))) if h is Dictionary else float(atk.get("range", 0.0))
				if rng <= 0.0:
					continue
				var both := bool((h as Dictionary).get("both", atk.get("both", false))) if h is Dictionary else bool(atk.get("both", false))
				var reach := rng * float(player.range_scale) * float(player._attack_range_scale)
				var radius := float(bag.body_radius)
				player.set("_attack_idx", ai)
				var tag := "P/%s/atk%d seg%d" % [str(id), ai + 1, hi + 1]
				_expect_player_at(player, bag, base + Vector2(reach + radius - 0.5, 0.0), h, true, tag + " 正前边界")
				_expect_player_at(player, bag, base + Vector2(reach + radius + 1.5, 0.0), h, false, tag + " 正前越界")
				_expect_player_at(player, bag, base + Vector2(reach * 0.5, -69.0), h, true, tag + " 纵向内")
				_expect_player_at(player, bag, base + Vector2(reach * 0.5, -71.0), h, false, tag + " 纵向外")
				_expect_player_at(player, bag, base + Vector2(-(reach + radius - 0.5), 0.0), h, both, tag + " 身后")

	player.queue_free()
	bag.queue_free()
	await get_tree().process_frame


func _expect_player_at(player, bag, pos: Vector2, h, expect: bool, tag: String) -> void:
	bag.global_position = pos
	bag.hp = 999999
	bag.state = 0
	bag.velocity = Vector2.ZERO
	player.call("_deal_hit", h)
	var got := int(bag.hp) < 999999
	_ok(got == expect, "%s 期望%s 实际%s (dx=%.1f dy=%.1f)" % [
		tag, "命中" if expect else "落空", "命中" if got else "落空",
		pos.x - player.global_position.x, pos.y - player.global_position.y])
