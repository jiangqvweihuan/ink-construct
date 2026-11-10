extends Node

## 玩家对战判定：HP/伤害系数/单次上限/回合节奏统一读取 pvp_tuning.gd。
## 只由主机或本机同屏创建；客户端只接收快照与状态 RPC，不跑这套规则，避免双方分叉。

const Tuning = preload("res://scripts/pvp/pvp_tuning.gd")

signal hp_changed(slot: int, hp: int, max_hp: int)
signal round_started(round_no: int)
signal round_ended(winner_slot: int, scores: Dictionary)
signal match_ended(winner_slot: int, scores: Dictionary)

const MAX_HP := Tuning.MAX_HP
const ROUNDS_TO_WIN := Tuning.ROUNDS_TO_WIN
## 玩家受击半径：与 PvE 的敌人半径取同一量级，避免贴脸时明明碰到却判不中
const HURT_RADIUS := Tuning.HURT_RADIUS

var players: Dictionary = {} # slot -> player 节点
var hp: Dictionary = {} # slot -> int
var scores: Dictionary = {} # slot -> 得分
var round_no := 1
var phase := "idle" # idle / fight / round_end / match_end
var winner := -1

## 最近一次对某槽位造成伤害的来源；持续伤害致死时用它判回合归属
var _last_attacker: Dictionary = {}


func register(slot: int, player) -> void:
	players[slot] = player
	hp[slot] = MAX_HP
	scores[slot] = 0
	_last_attacker.erase(slot)
	# 任何扣血入口（直伤/DOT）都会发 hp_changed，回合判定统一在这里收口
	if player.has_signal("hp_changed"):
		var cb := Callable(self, "_on_player_hp").bind(slot)
		if not player.hp_changed.is_connected(cb):
			player.hp_changed.connect(cb)


## 开始新回合：双方回满血并进入可结算状态
func begin_round() -> void:
	phase = "fight"
	winner = -1
	_last_attacker.clear()
	for slot in players:
		hp[slot] = MAX_HP
		var p = players[slot]
		if is_instance_valid(p):
			p.hp = MAX_HP
			p.max_hp = MAX_HP
			p.hp_changed.emit(MAX_HP, MAX_HP)
		hp_changed.emit(slot, MAX_HP, MAX_HP)
	round_started.emit(round_no)


## 整场重开：比分、回合与血量一起归零
func reset_match() -> void:
	round_no = 1
	winner = -1
	for slot in players:
		scores[slot] = 0
	begin_round()


func next_round() -> void:
	round_no += 1
	begin_round()


## 命中判定入口：玩家在命中帧发出 pvp_strike，这里按射程/高度/朝向结算到另一名玩家。
func handle_strike(attacker_slot: int, spec: Dictionary) -> void:
	if phase != "fight" or not players.has(attacker_slot):
		return
	var attacker = players[attacker_slot]
	if not is_instance_valid(attacker) or int(attacker.hp) <= 0:
		return
	for slot in players:
		if int(slot) == attacker_slot:
			continue
		var victim = players[slot]
		if not is_instance_valid(victim) or int(victim.hp) <= 0:
			continue
		if not _in_reach(attacker, victim, spec):
			continue
		var damage := _compute_damage(attacker, victim, spec)
		if damage <= 0:
			continue
		_apply_hit(attacker_slot, int(slot), damage, spec)
		return # 1v1：一次命中只结算一名对手


func snapshot() -> Dictionary:
	return {
		"hp": hp.duplicate(),
		"scores": scores.duplicate(),
		"round": round_no,
		"phase": phase,
		"winner": winner,
	}


## 伤害换算：PvE 结算值 × 对战系数 × 攻击方角色系数 × 受击方易伤，再受单次上限约束。
func _compute_damage(attacker, victim, spec: Dictionary) -> int:
	var raw := float(spec.get("damage", 0)) * Tuning.DAMAGE_SCALE
	if raw <= 0.0:
		return 0
	raw *= float(Tuning.CHAR_SCALE.get(str(attacker.get("skull_id")), 1.0))
	if attacker.has_method("pvp_damage_scale"):
		raw *= maxf(0.1, float(attacker.call("pvp_damage_scale")))
	if victim.has_method("pvp_damage_taken_scale"):
		raw *= maxf(0.1, float(victim.call("pvp_damage_taken_scale")))
	var damage := clampi(int(roundf(raw)), 1, Tuning.HIT_DAMAGE_CAP)
	# 红尘：每 3 层怨使攻击方每段伤害 -1（与 PvE 一样在最终伤害上做减法）
	if attacker.has_method("pvp_grudge_penalty"):
		damage = maxi(1, damage - int(attacker.call("pvp_grudge_penalty")))
	# 局外称号与目标特化加伤：与 PvE 一样按固定值追加（不参与倍率），再受单次上限约束
	if attacker.has_method("pvp_flat_damage_bonus"):
		damage += int(attacker.call("pvp_flat_damage_bonus", victim))
	return clampi(damage, 1, Tuning.HIT_DAMAGE_CAP)


func _in_reach(attacker, victim, spec: Dictionary) -> bool:
	var dx: float = victim.global_position.x - attacker.global_position.x
	var dy: float = absf(victim.global_position.y - attacker.global_position.y)
	if dy > float(spec.get("height", 70.0)) + HURT_RADIUS:
		return false
	if bool(spec.get("full_screen", false)):
		return true
	var reach := float(spec.get("range", 0.0)) + HURT_RADIUS
	if bool(spec.get("path", false)):
		# 路径技：闪现扫过的整条线段 + 落点正前方射程
		var sx := float(spec.get("start_x", attacker.global_position.x))
		var x0 := minf(sx, attacker.global_position.x) - 20.0
		var x1 := maxf(sx, attacker.global_position.x) + 20.0
		if victim.global_position.x >= x0 and victim.global_position.x <= x1:
			return true
		var ahead_path := dx == 0.0 or (dx > 0.0) == (int(attacker.facing) > 0)
		return ahead_path and absf(dx) <= reach
	var in_front := dx == 0.0 or (dx > 0.0) == (int(attacker.facing) > 0)
	if not (in_front or bool(spec.get("both", false))):
		return false
	return absf(dx) <= reach


func _apply_hit(attacker_slot: int, victim_slot: int, damage: int, spec: Dictionary) -> void:
	var attacker = players[attacker_slot]
	var victim = players[victim_slot]
	_last_attacker[victim_slot] = attacker_slot
	var dir := 1.0 if victim.global_position.x >= attacker.global_position.x else -1.0
	var kb := Vector2(dir * 120.0, -90.0) * maxf(0.4, float(spec.get("knockback", 1.0)))
	var before := int(victim.hp)
	victim.call("pvp_apply_damage", damage, kb, attacker)
	# 实际伤害回报：护盾/反伤/复活保护挡下时 dealt 为 0，攻击方的“伤害后”被动据此结算
	var dealt := maxi(0, before - int(victim.hp))
	if dealt > 0 and attacker.has_method("on_pvp_damage_dealt"):
		attacker.call("on_pvp_damage_dealt", dealt, victim)
	# 血量与回合判定由 victim.hp_changed → _on_player_hp 统一处理


## 玩家血量变化：同步权威血量；归零时立刻结算回合（直伤与持续伤害共用）。
func _on_player_hp(current: int, maximum: int, slot: int) -> void:
	var now := maxi(0, current)
	hp[slot] = now
	hp_changed.emit(slot, now, maximum)
	if now > 0 or phase != "fight":
		return
	var killer := int(_last_attacker.get(slot, 1 - slot))
	if killer == slot or not players.has(killer):
		killer = 1 - slot if players.has(1 - slot) else slot
	_finish_round(killer)


## 回合结算（幂等）：加分 → 回合结束 → 到 2 分结束整场。
func _finish_round(winner_slot: int) -> void:
	if phase != "fight":
		return
	scores[winner_slot] = int(scores.get(winner_slot, 0)) + 1
	phase = "round_end"
	round_ended.emit(winner_slot, scores.duplicate())
	if int(scores[winner_slot]) >= ROUNDS_TO_WIN:
		winner = winner_slot
		phase = "match_end"
		match_ended.emit(winner_slot, scores.duplicate())
