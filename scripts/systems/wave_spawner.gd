extends Node

## 波次刷怪器：按 waves 定义一浪一浪放怪，每波保持最多 concurrent 只存活，
## 前一只死了才补下一只。全部波次清完发 all_cleared。
## 用法：new() 后设置 waves / spawn_xs / spawn_y，再 add_child 到房间根节点，自动开始。

signal wave_started(index: int, total: int)
signal wave_cleared(index: int)
signal all_cleared()

## 普通怪 / 精英的候选场景，刷怪时各随机挑一个
const NORMAL_SCENES := [
	"res://scenes/enemies/c016.tscn", # 刀客
	"res://scenes/enemies/c017.tscn", # 蛮兵
	"res://scenes/enemies/c035.tscn", # 刺客
]
const ELITE_SCENES := [
	"res://scenes/enemies/c037_elite.tscn", # 青魇剑主
	"res://scenes/enemies/c018_elite.tscn", # 双镰
	"res://scenes/enemies/c012_elite.tscn", # 青笠剑客（前玩家形态，两连击 + 跳斩）
]
const SPAWN_INTERVAL := 0.9 # 未开局时的补怪间隔兜底（正式局走 Run.spawn_interval()）
const WAVE_GAP := 1.6 # 波次之间的喘息时间（秒）
const MAX_CONCURRENT := 6 # 未开局时的同屏上限兜底（正式局走 Run.max_concurrent()）

## 每波一项：{count=本波总数, hp=每只血量, speed=速度倍率, elite=其中的精英数量}
var waves: Array = [
	{"count": 5, "hp": 6, "speed": 1.0},
	{"count": 7, "hp": 6, "speed": 1.05, "elite": 1},
	{"count": 9, "hp": 8, "speed": 1.12, "elite": 2},
]
var spawn_xs: Array = [820.0, 1120.0, 1440.0, 1720.0] # 候选出生点 x（会随机挑，避开玩家附近）
var spawn_y := 560.0
var player_ref: Node2D
## 全部玩家（联机 4 人时由房间写入）；为空时回落到 player_ref。
var player_refs: Array = []
## 出生点与任意存活玩家的最小 2D 距离：既防贴脸，也防从头顶/面前刷出。
var spawn_safe_dist := 320.0

var _wave := -1
var _to_spawn := 0 # 本波还没刷出来的数量
var _elites_left := 0 # 本波还没刷出来的精英数量
var _alive: Array = []
var _cd := 0.0
var _running := false


func _ready() -> void:
	_running = true
	_cd = 0.5
	_next_wave()


func _process(delta: float) -> void:
	if not _running:
		return
	# 这里只清理失效引用；存活列表必须由真实 died 回调移除，魔爆等死亡演出未完成不得清波。
	_alive = _alive.filter(func(e): return is_instance_valid(e))
	if _wave < 0:
		return
	_cd -= delta
	# 还有没刷的怪：按间隔补刷，且不超过同时存活上限
	if _to_spawn > 0 and _cd <= 0.0 and _alive.size() < Run.max_concurrent():
		if not _spawn_one():
			# 没有安全出生点：不消耗名额，稍后重试，绝不贴脸硬刷
			_cd = 0.2
			return
		_cd = Run.spawn_interval()
		return
	# 本波刷完且场上都清干净 -> 进下一波
	if _to_spawn <= 0 and _alive.is_empty() and _cd <= 0.0:
		wave_cleared.emit(_wave)
		_cd = WAVE_GAP
		_next_wave()


func _next_wave() -> void:
	_wave += 1
	if _wave >= waves.size():
		_wave = -1
		_running = false
		all_cleared.emit()
		return
	var cfg: Dictionary = waves[_wave]
	_to_spawn = int(cfg.get("count", 5))
	_elites_left = int(cfg.get("elite", 0))
	wave_started.emit(_wave, waves.size())


func _spawn_one() -> bool:
	var x := _pick_x()
	if is_nan(x):
		return false # 所有候选点都离玩家太近：本次不刷
	var cfg: Dictionary = waves[_wave]
	var is_elite := _elites_left > 0
	var list: Array = ELITE_SCENES if is_elite else NORMAL_SCENES
	var scene = load(str(list[randi() % list.size()])) if not list.is_empty() else null
	var e = scene.instantiate() if scene != null else null
	if e == null:
		# 配置/资源异常时也消耗一个名额，避免波次永远清不完、房间卡死
		_to_spawn -= 1
		return true
	e.position = Vector2(x + randf_range(-25.0, 25.0), spawn_y)
	e.died.connect(_on_enemy_died.bind(e))
	add_child(e)
	if is_elite:
		# 精英的招式 / 血量 / 霸体都在形态表里，这里只按波次微调速度与血量倍率
		_elites_left -= 1
		e.configure({"speed": float(cfg.get("speed", 1.0)) * 0.9, "hp_mul": float(cfg.get("hp_mul", 1.0))})
	else:
		# 每只怪的站位距离与出手节奏都错开：不会几只挤在同一格，也不会整齐划一地同时挥刀
		e.configure({
			"hp": int(cfg.get("hp", 6)),
			"speed": float(cfg.get("speed", 1.0)),
			"attack_range": randf_range(140.0, 205.0),
			"keep_dist": randf_range(70.0, 110.0),
			"attack_cooldown": randf_range(1.6, 2.4),
		})
	_alive.append(e)
	_to_spawn -= 1
	return true


## 挑一个离所有存活玩家都超过 spawn_safe_dist、也不压着其他存活怪的出生点。
## 找不到安全点时返回 NAN（调用方跳过这次刷新），绝不回落到"离怪最远"的贴脸点。
func _pick_x() -> float:
	if spawn_xs.is_empty():
		return 640.0
	var ok: Array = spawn_xs.filter(func(x: float):
		return _safe_from_players(float(x)) and _peer_gap(float(x)) > 110.0)
	if ok.is_empty():
		# 4 人局站位分散时固定点可能全被占住：在场地内再按 100px 采样一圈。
		for i in range(6, 19):
			var x := float(i) * 100.0
			if _safe_from_players(x) and _peer_gap(x) > 110.0:
				ok.append(x)
	if ok.is_empty():
		return NAN
	return float(ok[randi() % ok.size()])


## 出生点是否与所有存活玩家保持安全距离（含跳跃中的头顶位置，按 2D 距离算）
func _safe_from_players(x: float) -> bool:
	var point := Vector2(x, spawn_y)
	for p in _player_nodes():
		if p == null or not is_instance_valid(p):
			continue
		if int(p.get("hp")) <= 0 or int(p.get("state")) == 8:
			continue
		if point.distance_to(p.global_position) < spawn_safe_dist:
			return false
	return true


func _player_nodes() -> Array:
	if not player_refs.is_empty():
		return player_refs
	return [player_ref] if player_ref != null else []


## 出生点到最近一只存活怪的水平距离
func _peer_gap(x: float) -> float:
	var gap := INF
	for e in _alive:
		if is_instance_valid(e):
			gap = minf(gap, absf(e.global_position.x - x))
	return gap


func _on_enemy_died(e) -> void:
	if _alive.has(e):
		_alive.erase(e)
