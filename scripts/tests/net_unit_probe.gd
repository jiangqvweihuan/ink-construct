extends Node

## 联机单元测试探针（单进程）：
## 1) 封包打包/解包往返、CRC、魔数、版本、长度校验；
## 2) 输入/快照清洗、信标解析；
## 3) 自动发现：同进程内起一对主机与扫描端，验证探测/信标与 TTL 过期。
## 运行：godot --headless --path . res://scenes/tests/net_unit_probe.tscn

const Cfg = preload("res://scripts/net/net_config.gd")
const Proto = preload("res://scripts/net/net_protocol.gd")
const Discovery = preload("res://scripts/net/lan_discovery.gd")
const LocalCoop = preload("res://scripts/systems/local_coop.gd")

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
	_test_lan_permissions()
	await _test_lan_input_source()
	await _test_lan_choices()


# ---------------------------------------------------------------- 联机权限 / 输入 / 三选一回归

## 回归：房主与客机的化身选择各自独立，且房间清理/重连后不丢
func _test_lan_permissions() -> void:
	var err := LanNet.host_room("权限测试房", Run.MODE_ADVENTURE, 1, "c021")
	_check("perm_host_room", err == "" and LanNet.my_skull() == "c021", err)
	_check("perm_host_member_skull", str(LanNet.members[1].get("skull", "")) == "c021")
	LanNet.set_my_skull("c013")
	_check("perm_host_change", str(LanNet.room.get("skull", "")) == "c013" and LanNet.my_skull() == "c013")

	# 模拟客机：成员条目暂空时必须回落到本机 my_pick，而不是变成"未选择"
	var uid := multiplayer.get_unique_id()
	LanNet.role = "client"
	LanNet.my_pick = ""
	LanNet.members = {
		42: {"name": "房主", "slot": 0, "ready": true, "skull": "c021"},
		uid: {"name": "客机", "slot": 1, "ready": true, "skull": ""},
	}
	LanNet.my_pick = "c023"
	_check("perm_client_fallback", LanNet.my_skull() == "c023", LanNet.my_skull())
	LanNet.set_my_skull("z000")
	_check("perm_client_pick", LanNet.my_skull() == "z000"
		and str(LanNet.members[uid].get("skull", "")) == "z000")
	_check("perm_independent", str(LanNet.members[42].get("skull", "")) == "c021")

	# 房间清理 / 重置后选择仍在，重进房间可直接沿用
	LanNet.teardown("", false)
	_check("perm_pick_survive_reset", LanNet.my_pick == "z000", LanNet.my_pick)
	LanNet.role = ""


## 回归：客机采样本机设备输入（PC 的 P1 键位 / 移动端触屏），不再绑 P2 通道
func _test_lan_input_source() -> void:
	LocalCoop.ensure_input()
	LanNet.role = "client"
	LanNet.state = "playing"
	# 关掉 LanNet 的自动采样，避免后台 _process 提前消费 just_pressed（测试要手动触发）
	LanNet.set_process(false)
	Input.action_release("attack")
	LanNet._pending_just.clear()
	LanNet._input_flush = false
	var ev := InputEventAction.new()
	ev.action = "attack"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	LanNet._sample_input_edges()
	_check("input_base_action", LanNet._pending_just.has("attack"), str(LanNet._pending_just.keys()))
	_check("input_flush_edge", LanNet._input_flush)
	# 必须松开，否则后续注入同一动作时不会再产生 just_pressed（Godot 只在未按下时记录按下帧）
	Input.action_release("attack")
	LanNet._pending_just.clear()
	LanNet._input_flush = false

	# 只按 P2 键不应该被客机采样到（旧 bug：PC 客机被迫用方向键，移动端完全无输入）
	var ev2 := InputEventAction.new()
	ev2.action = LocalCoop.action(1, "attack")
	ev2.pressed = true
	Input.parse_input_event(ev2)
	await get_tree().process_frame
	LanNet._sample_input_edges()
	_check("input_no_p2", not LanNet._pending_just.has("attack"), str(LanNet._pending_just.keys()))
	Input.action_release(LocalCoop.action(1, "attack"))
	LanNet._pending_just.clear()

	# 移动端：TouchControls 注入的是基础动作，客机采样能直接读到
	TouchControls._tap("attack")
	_check("touch_injects_base", Input.is_action_pressed("attack"))
	LanNet._pending_just.clear()
	LanNet._sample_input_edges()
	_check("touch_sampled", LanNet._pending_just.has("attack"), str(LanNet._pending_just.keys()))
	Input.action_release("attack")
	TouchControls._taps.clear()
	LanNet.set_process(true)

	# 移动端客机的技能环 / 横划必须落在自己槽位的角色上
	var a := SlotStub.new()
	a.input_slot = 0
	var b := SlotStub.new()
	b.input_slot = 1
	add_child(a)
	add_child(b)
	a.add_to_group("player")
	b.add_to_group("player")
	Run.net_role = "client"
	Run.net_slot = 1
	_check("touch_targets_local_slot", TouchControls._player() == b)
	a.remove_from_group("player")
	b.remove_from_group("player")
	a.queue_free()
	b.queue_free()
	Run.net_role = ""
	Run.net_slot = 0
	LanNet._pending_just.clear()
	LanNet.role = ""
	LanNet.state = "idle"


## 回归：祝福 / 通关强化两端各自选、各写各的槽位；房主必须等所有人选完才推进
func _test_lan_choices() -> void:
	Run.start(Run.MODE_ADVENTURE, "c021", 1, true)
	Run.set_net_players(2)
	Run.set_slot_skull(1, "c012")
	LanNet.teardown("", false)
	LanNet.host_room("选择测试房", Run.MODE_ADVENTURE, 1, "c021")
	LanNet.state = "playing"
	LanNet.members[42] = {"name": "客机", "slot": 1, "ready": true, "skull": "c012"}

	# 祝福：全队同牌，各选各的
	LanNet.host_begin_choice("blessing")
	_check("choice_open", LanNet._choice_open)
	var cards0: Array = LanNet._choice_cards.get(0, [])
	var cards1: Array = LanNet._choice_cards.get(1, [])
	_check("choice_cards", cards0.size() == 3 and cards1.size() == 3)
	_check("choice_blocks_proceed", not LanNet.choices_complete())
	LanNet.submit_choice("blessing", str(cards0[0]))
	_check("choice_wait_others", LanNet._choice_open and not LanNet.choices_complete())
	LanNet._record_choice(1, str(cards1[1]))
	_check("choice_finished", not LanNet._choice_open and LanNet.choices_complete())
	_check("choice_slot0", Run.blessing == str(cards0[0]), Run.blessing)
	_check("choice_slot1", Run.blessing_of(1) == str(cards1[1]), Run.blessing_of(1))

	# HP 赐福按槽位单独计入上限（+2）
	Run.slot_blessing[3] = ""
	Run.set_blessing(1, "hp")
	var without := Run.calculated_max_hp("c012", 2)
	var with_hp := Run.calculated_max_hp("c012", 1)
	_check("choice_blessing_hp_slot", with_hp == without + 2, "%d/%d" % [with_hp, without])

	# 通关强化：按各自槽位与流派等级发牌，各自落盘
	LanNet.host_begin_choice("upgrade")
	var up0: Array = LanNet._choice_cards.get(0, [])
	var up1: Array = LanNet._choice_cards.get(1, [])
	_check("choice_upgrade_cards", up0.size() == 3 and up1.size() == 3)
	LanNet.submit_choice("upgrade", str(up0[0]))
	LanNet._record_choice(1, str(up1[0]))
	_check("choice_upgrade_slot0", Run.level(str(up0[0]), 0) >= 1)
	_check("choice_upgrade_slot1", Run.level(str(up1[0]), 1) >= 1 and Run.slot_upgrades.has(1))
	if str(up0[0]) != str(up1[0]):
		_check("choice_upgrade_independent", Run.level(str(up1[0]), 0) == 0)

	# 客机侧回归：收到三选一请求必须写下 _choice_kind，submit_choice 才能通过类型校验。
	# 旧 bug：客机从未写入该字段，选择被静默丢弃，主机只能等 25 秒超时，画面整段卡死。
	LanNet.role = "client"
	LanNet.state = "playing"
	LanNet._choice_kind = ""
	LanNet._pending_choice.clear()
	LanNet._rpc_choice_request({"kind": "upgrade", "token": 7, "cards": up1.duplicate(), "slot": 1})
	_check("choice_client_armed", LanNet._choice_kind == "upgrade", LanNet._choice_kind)
	_check("choice_client_pending", (LanNet._pending_choice.get("cards", []) as Array).size() == 3)
	# 关闭后必须解除武装：迟到的点击不能串进下一次三选一
	LanNet._rpc_event({"kind": "choice_done", "choice": "upgrade", "run": {}})
	_check("choice_client_disarmed", LanNet._choice_kind == "", LanNet._choice_kind)

	LanNet.teardown("", false)
	Run.net_role = ""
	Run.active = false
	Run.set_net_players(1)


class SlotStub:
	extends Node
	var input_slot := 0


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
	var snap := Proto.sanitize_snapshot({"seq": 1, "ps": ps, "es": es})
	_check("sanitize_snapshot_players", (snap["ps"] as Array).size() == Cfg.MAX_PLAYERS)
	_check("sanitize_snapshot_enemies", (snap["es"] as Array).size() == 64)


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
