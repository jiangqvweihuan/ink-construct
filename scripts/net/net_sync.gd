extends Node

## 房间内联机同步：主机按 20Hz 生产快照，客户端消费快照并驱动镜像实体。
## 单机/本机双人不会创建本节点，所有分支都不影响原有战斗。

const Cfg = preload("res://scripts/net/net_config.gd")

var room = null # room_01 实例，由房间在 add_child 前注入

var _acc := 0.0
var _next_id := 0
var _applied_seq := -1
var _players := {} # slot -> 玩家节点
var _enemies := {} # net_id -> 敌人节点
var _etarget := {} # net_id -> 目标状态
var _ptarget := {} # slot -> 目标状态
var _missing := {} # net_id -> 首次缺失时间


func _ready() -> void:
	if room == null:
		return
	for i in room._players.size():
		_players[i] = room._players[i]
	if Run.net_role == "client":
		for p in room._players:
			if is_instance_valid(p):
				p.net_puppet = true


func _process(delta: float) -> void:
	match Run.net_role:
		"host":
			_acc += delta
			if _acc >= 1.0 / Cfg.SNAPSHOT_HZ:
				_acc = 0.0
				LanNet.push_snapshot(_build())
		"client":
			if LanNet.snapshot_seq != _applied_seq and not LanNet.latest_snapshot.is_empty():
				_applied_seq = LanNet.snapshot_seq
				_ingest(LanNet.latest_snapshot)
			_interpolate(delta)


# ---------------------------------------------------------------- 主机

func _build() -> Dictionary:
	var ps: Array = []
	for slot in _players:
		var p = _players[slot]
		if not is_instance_valid(p):
			continue
		ps.append([
			int(slot), p.global_position.x, p.global_position.y,
			int(p.hp), int(p.max_hp), int(p.state), int(p.facing),
			str(p.get("_current_anim")), bool(p.get("net_anim_loop")),
			str(p.get("skull_id")), p.state == p.State.DEAD,
		])

	var es: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var eid := int(e.get_meta("net_id", 0))
		if eid <= 0:
			_next_id += 1
			eid = _next_id
			e.set_meta("net_id", eid)
		var path := str(e.scene_file_path)
		if path == "":
			continue
		es.append([
			eid, path, str(e.get("type_id")),
			e.global_position.x, e.global_position.y,
			int(e.hp), int(e.max_hp), int(e.state), int(e.facing),
			str(e.get("_current_anim")), bool(e.get("net_anim_loop")),
		])
	return {"ps": ps, "es": es, "run": LanNet.run_payload()}


# ---------------------------------------------------------------- 客户端

func _ingest(s: Dictionary) -> void:
	for row in s.get("ps", []):
		if not (row is Array) or row.size() < 11:
			continue
		var slot := int(row[0])
		_ptarget[slot] = {
			"pos": Vector2(float(row[1]), float(row[2])),
			"hp": int(row[3]), "max_hp": int(row[4]), "state": int(row[5]),
			"facing": int(row[6]), "anim": str(row[7]), "loop": bool(row[8]),
		}

	var seen := {}
	var now := Time.get_ticks_msec()
	for row in s.get("es", []):
		if not (row is Array) or row.size() < 11:
			continue
		var eid := int(row[0])
		var path := str(row[1])
		if path == "":
			continue
		seen[eid] = true
		_etarget[eid] = {
			"pos": Vector2(float(row[3]), float(row[4])),
			"hp": int(row[5]), "max_hp": int(row[6]), "state": int(row[7]),
			"facing": int(row[8]), "anim": str(row[9]), "loop": bool(row[10]),
		}
		if not _enemies.has(eid) or not is_instance_valid(_enemies[eid]):
			_spawn_puppet(eid, path)

	# 快照里连续缺失 0.3 秒才移除，避免单个丢包导致模型闪烁
	for eid in _enemies.keys():
		if seen.has(eid):
			_missing.erase(eid)
			continue
		if not _missing.has(eid):
			_missing[eid] = now
		elif now - int(_missing[eid]) > 300:
			var e = _enemies[eid]
			if is_instance_valid(e):
				e.queue_free()
			_enemies.erase(eid)
			_etarget.erase(eid)
			_missing.erase(eid)


func _spawn_puppet(eid: int, path: String) -> void:
	var packed = load(path)
	if packed == null:
		return
	var e = packed.instantiate()
	if e == null:
		return
	e.net_puppet = true
	e.set_meta("net_id", eid)
	e.name = "NetPuppet_%d" % eid
	room.add_child(e)
	_enemies[eid] = e


func _interpolate(delta: float) -> void:
	var k := clampf(delta * 18.0, 0.0, 1.0)
	for slot in _ptarget:
		var p = _players.get(slot)
		if not is_instance_valid(p):
			continue
		var d: Dictionary = _ptarget[slot]
		var pos: Vector2 = p.global_position.lerp(d["pos"], k)
		p.net_apply_state(pos.x, pos.y, int(d["hp"]), int(d["max_hp"]), int(d["state"]), int(d["facing"]), str(d["anim"]), bool(d["loop"]))

	for eid in _etarget:
		var e = _enemies.get(eid)
		if not is_instance_valid(e):
			continue
		var d: Dictionary = _etarget[eid]
		var pos: Vector2 = e.global_position.lerp(d["pos"], k)
		e.net_apply_state(pos.x, pos.y, int(d["hp"]), int(d["max_hp"]), int(d["state"]), int(d["facing"]), str(d["anim"]), bool(d["loop"]))
