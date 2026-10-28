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
	"res://scenes/enemies/z002.tscn", # 黑袍剑客
	"res://scenes/enemies/c017.tscn", # 蛮兵
	"res://scenes/enemies/c035.tscn", # 刺客
]
const ELITE_SCENES := [
	"res://scenes/enemies/c023_elite.tscn", # 落梅弓手
	"res://scenes/enemies/c037_elite.tscn", # 大剑骑士
	"res://scenes/enemies/c018_elite.tscn", # 双镰
]
const SPAWN_INTERVAL := 0.9 # 同一波内两只之间的补怪间隔（秒）
const WAVE_GAP := 1.6 # 波次之间的喘息时间（秒）
const MAX_CONCURRENT := 6 # 屏上同时存活上限

## 每波一项：{count=本波总数, hp=每只血量, speed=速度倍率, elite=其中的精英数量}
var waves: Array = [
	{"count": 5, "hp": 3, "speed": 1.0},
	{"count": 7, "hp": 3, "speed": 1.05, "elite": 1},
	{"count": 9, "hp": 4, "speed": 1.12, "elite": 2},
]
var spawn_xs: Array = [820.0, 1120.0, 1440.0, 1720.0] # 候选出生点 x（会随机挑，避开玩家附近）
var spawn_y := 560.0
var player_ref: Node2D

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
	# 清理已失效（已死/被移除）的引用
	_alive = _alive.filter(func(e): return is_instance_valid(e) and e.hp > 0)
	if _wave < 0:
		return
	_cd -= delta
	# 还有没刷的怪：按间隔补刷，且不超过同时存活上限
	if _to_spawn > 0 and _cd <= 0.0 and _alive.size() < MAX_CONCURRENT:
		_spawn_one()
		_cd = SPAWN_INTERVAL
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


func _spawn_one() -> void:
	var cfg: Dictionary = waves[_wave]
	var is_elite := _elites_left > 0
	var scene_path: String = ELITE_SCENES[randi() % ELITE_SCENES.size()] if is_elite else NORMAL_SCENES[randi() % NORMAL_SCENES.size()]
	var e = load(scene_path).instantiate()
	if e == null:
		return
	e.position = Vector2(_pick_x() + randf_range(-25.0, 25.0), spawn_y)
	e.died.connect(_on_enemy_died.bind(e))
	add_child(e)
	if is_elite:
		# 精英的招式 / 血量 / 霸体都在形态表里，这里只按波次微调速度
		_elites_left -= 1
		e.configure({"speed": float(cfg.get("speed", 1.0)) * 0.9})
	else:
		# 每只怪的站位距离与出手节奏都错开：不会几只挤在同一格，也不会整齐划一地同时挥刀
		e.configure({
			"hp": int(cfg.get("hp", 3)),
			"speed": float(cfg.get("speed", 1.0)),
			"attack_range": randf_range(140.0, 205.0),
			"keep_dist": randf_range(70.0, 110.0),
			"attack_cooldown": randf_range(1.6, 2.4),
		})
	_alive.append(e)
	_to_spawn -= 1


## 挑一个离玩家不太近、也不压着其他存活怪的出生点，避免贴脸刷出 / 叠罗汉
func _pick_x() -> float:
	var px: float = player_ref.global_position.x if is_instance_valid(player_ref) else 640.0
	var ok: Array = spawn_xs.filter(func(x: float): return absf(x - px) > 260.0 and _peer_gap(x) > 110.0)
	if ok.is_empty():
		ok = spawn_xs.filter(func(x: float): return _peer_gap(x) > 110.0)
	if ok.is_empty():
		# 所有点上都站着怪：选离最近怪最远的那个点，至少错开最多
		var best_x := float(spawn_xs[0])
		var best_gap := -1.0
		for x in spawn_xs:
			var gap := _peer_gap(float(x))
			if gap > best_gap:
				best_gap = gap
				best_x = float(x)
		return best_x
	return float(ok[randi() % ok.size()])


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
