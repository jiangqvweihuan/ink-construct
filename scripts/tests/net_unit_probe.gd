extends Node

## 联机单元测试探针（单进程）：
## 1) 封包打包/解包往返、CRC、魔数、版本、长度校验；
## 2) 输入/快照清洗、信标解析；
## 3) 自动发现：同进程内起一对主机与扫描端，验证探测/信标与 TTL 过期。
## 运行：godot --headless --path . res://scenes/tests/net_unit_probe.tscn

const Cfg = preload("res://scripts/net/net_config.gd")
const Proto = preload("res://scripts/net/net_protocol.gd")
const Discovery = preload("res://scripts/net/lan_discovery.gd")

var fail := 0


func _ready() -> void:
	await _run()
	print("PROBE RESULT fail=%d" % fail)
	get_tree().quit(1 if fail > 0 else 0)


func _check(name: String, cond: bool, detail := "") -> void:
	print("PROBE %s %s%s" % [name, "PASS" if cond else "FAIL", (" " + detail) if detail != "" else ""])
	if not cond:
		fail += 1


func _run() -> void:
	_test_protocol()
	_test_sanitize()
	_test_beacon()
	await _test_discovery()
	await _test_lan_panel()
	await _test_room_host()


# ---------------------------------------------------------------- 大厅 UI

func _test_lan_panel() -> void:
	var panel = load("res://scenes/ui/lan_panel.tscn").instantiate()
	add_child(panel)
	await get_tree().process_frame
	_check("lan_panel_instantiate", is_instance_valid(panel) and panel._body.get_child_count() > 0)
	var err := LanNet.host_room("UI测试房", Run.MODE_ADVENTURE, 1, "c021")
	_check("lan_panel_host_room", err == "", err)
	await get_tree().process_frame
	_check("lan_panel_room_view", is_instance_valid(panel) and panel._body.get_child_count() > 0)
	LanNet.teardown("", false)
	panel.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- 房间场景

## 主机侧房间冒烟：确认联机房间能构建双玩家、挂上 NetSync、并生成敌人
func _test_room_host() -> void:
	Run.start(Run.MODE_ADVENTURE, "c021", 1, true)
	Run.net_role = "host"
	Run.net_slot = 0
	Run.set_net_players(2) # 主机 + 1 名客机：房间应按实际人数建 2 名角色
	var room = load("res://scenes/world/room_01.tscn").instantiate()
	add_child(room)
	for i in 90:
		await get_tree().process_frame
	_check("room_host_netsync", room.get_node_or_null("NetSync") != null)
	_check("room_host_players", room._players.size() == 2, "n=%d" % room._players.size())
	_check("room_host_enemies", get_tree().get_nodes_in_group("enemies").size() > 0)
	room.queue_free()
	await get_tree().process_frame

	# 局域网 4 人：主机权威 + 3 名镜像玩家，槽位必须互不重复
	Run.start(Run.MODE_ADVENTURE, "c021", 1, true)
	Run.net_role = "host"
	Run.net_slot = 0
	Run.set_net_players(4)
	var room4 = load("res://scenes/world/room_01.tscn").instantiate()
	add_child(room4)
	for i in 30:
		await get_tree().process_frame
	_check("room_host4_players", room4._players.size() == 4, "n=%d" % room4._players.size())
	var slots := {}
	for pl in room4._players:
		slots[int(pl.input_slot)] = true
	_check("room_host4_slots", slots.size() == 4 and slots.has(0) and slots.has(3), str(slots.keys()))
	_check("room_host4_spawn_refs", room4._spawner.player_refs.size() == 4)
	room4.queue_free()
	await get_tree().process_frame

	Run.net_role = ""
	Run.active = false


# ---------------------------------------------------------------- 协议

func _test_protocol() -> void:
	var payload := {"seq": 7, "axis": 1, "held": ["attack", "jump"], "just": ["attack"]}
	var buf := Proto.pack(Proto.T_INPUT, 7, payload)
	var out := Proto.unpack(buf)
	_check("protocol_roundtrip", int(out.get("_type", 0)) == Proto.T_INPUT and int(out.get("_seq", 0)) == 7
		and int(out.get("axis", 0)) == 1 and (out.get("held", []) as Array).size() == 2)

	_check("crc32_known", Proto.crc32("123456789".to_utf8_buffer()) == 0xCBF43926)

	# 破坏 payload 中段一个字节，CRC 必须拒绝
	var bad := buf.duplicate()
	bad[Proto.HEADER + 1] = bad[Proto.HEADER + 1] ^ 0xFF
	_check("protocol_crc_reject", Proto.unpack(bad).is_empty())

	var short := buf.slice(0, 6)
	_check("protocol_length_reject", Proto.unpack(short).is_empty())

	var wrong_magic := buf.duplicate()
	wrong_magic.encode_u8(0, 0x00)
	_check("protocol_magic_reject", Proto.unpack(wrong_magic).is_empty())

	var wrong_ver := buf.duplicate()
	wrong_ver.encode_u8(2, 99)
	_check("protocol_version_reject", Proto.unpack(wrong_ver).is_empty())


func _test_sanitize() -> void:
	var clean := Proto.sanitize_input({"seq": 3, "axis": 9, "held": ["attack", "attack", "hack"], "just": ["jump", "hack"]})
	_check("sanitize_axis_clamp", int(clean["axis"]) == 1)
	_check("sanitize_held", (clean["held"] as Array) == ["attack"])
	_check("sanitize_just", (clean["just"] as Array) == ["jump"])

	var ps: Array = []
	for i in 5:
		ps.append([i, 0, 0, 8, 8, 0, 1, "stand", true, false, false])
	var es: Array = []
	for i in 100:
		es.append([i, "res://scenes/enemies/c016.tscn", 0, 0, 0, 4, 4, 0, 1, "stand", true])
	var snap := Proto.sanitize_snapshot({"seq": 1, "ps": ps, "es": es, "run": {"depth": 2}})
	_check("sanitize_snapshot_players", (snap["ps"] as Array).size() == Cfg.MAX_PLAYERS)
	_check("sanitize_snapshot_enemies", (snap["es"] as Array).size() == 64)
	_check("sanitize_snapshot_run", int((snap["run"] as Dictionary).get("depth", 0)) == 2)


func _test_beacon() -> void:
	var ok := Proto.parse_beacon({
		"app": Cfg.APP_ID, "v": Cfg.PROTO_VERSION, "name": "测试房",
		"port": 70000, "players": 2, "max": 2, "mode": "adventure",
		"difficulty": 9, "state": "lobby", "skull": "c021",
	})
	_check("beacon_parse_ok", str(ok.get("name", "")) == "测试房" and int(ok.get("port", 0)) == 65535
		and int(ok.get("difficulty", -1)) == 4)
	_check("beacon_reject_app", Proto.parse_beacon({"app": "other", "v": Cfg.PROTO_VERSION}).is_empty())
	_check("beacon_reject_version", Proto.parse_beacon({"app": Cfg.APP_ID, "v": 999}).is_empty())


# ---------------------------------------------------------------- 自动发现

func _test_discovery() -> void:
	var host := Discovery.new()
	var scan := Discovery.new()
	var started := host.start_host(func(): return {
		"app": Cfg.APP_ID, "v": Cfg.PROTO_VERSION, "name": "单元测试房",
		"port": Cfg.GAME_PORT, "players": 1, "max": 2,
		"mode": "adventure", "difficulty": 1, "state": "lobby", "skull": "c021",
	})
	_check("discovery_host_bind", started, host.error)
	if not started:
		return
	_check("discovery_scan_bind", scan.start_scan(), scan.error)

	var found := false
	var waited := 0.0
	var last_ms := Time.get_ticks_msec()
	while waited < 6.0:
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		var dt := float(now - last_ms) / 1000.0
		last_ms = now
		waited += dt
		host.poll(dt)
		scan.poll(dt)
		var rooms := scan.rooms()
		if not rooms.is_empty():
			var r: Dictionary = rooms[0]
			found = str(r.get("name", "")) == "单元测试房" and int(r.get("port", 0)) == Cfg.GAME_PORT
			if found:
				break
	_check("discovery_found_room", found)

	# 主机停播后，扫描端条目应在 TTL 后过期
	host.stop()
	var expired := false
	waited = 0.0
	last_ms = Time.get_ticks_msec()
	while waited < Cfg.ROOM_TTL + 1.5:
		await get_tree().process_frame
		var now2 := Time.get_ticks_msec()
		var dt2 := float(now2 - last_ms) / 1000.0
		last_ms = now2
		waited += dt2
		scan.poll(dt2)
		if scan.rooms().is_empty():
			expired = true
			break
	_check("discovery_ttl_expire", expired)
	scan.stop()
