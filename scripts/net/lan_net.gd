extends Node

## 局域网联机会话中心（自动加载）。
## 主机权威：主机跑完整战斗（本机 P1 + 最多 3 名远端玩家的输入），客户端只上送输入并接收快照镜像。
## 所有对局同步都由 NetSync 驱动，这里只负责连接、房间、会话、心跳、重连与按槽位的远端输入缓冲。

signal rooms_changed(rooms: Array)
signal lobby_changed(state: Dictionary)
signal joined(resumed: bool)
signal join_failed(reason: String)
signal session_started(config: Dictionary)
signal session_ended(reason: String)
signal net_notice(text: String)
signal link_lost(reason: String)
signal link_restored()

const Cfg = preload("res://scripts/net/net_config.gd")
const Proto = preload("res://scripts/net/net_protocol.gd")
const Discovery = preload("res://scripts/net/lan_discovery.gd")
const LocalCoop = preload("res://scripts/systems/local_coop.gd")
const Skulls = preload("res://scripts/player/skulls.gd")

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const ROOM_SCENE := "res://scenes/world/room_01.tscn"

var role := "" # "" / "host" / "client"
var state := "idle" # idle / hosting / joining / lobby / playing / reconnecting
var room: Dictionary = {}
var members: Dictionary = {} # peer_id -> {name, slot, ready, token}
var local_slot := 0
var auto_enter_room := true # 测试关闭，避免测试进程加载整张房间
var latest_snapshot: Dictionary = {}
var snapshot_seq := 0
var last_rtt_ms := 0
var bad_packets := 0
var discovery: Discovery = null

var _peer: ENetMultiplayerPeer = null
var _mp_wired := false
var _suppress_disconnect := false
var _transitioning := false

var _input_seq := 0
var _input_acc := 0.0
var _pending_just := {}
## 远端输入按 slot 分桶（slot 1~3）；每个元素结构：{action: true} / {action: 毫秒时间戳}
var _remote_held := {}
var _remote_just := {}
var _remote_just_at := {}
var _remote_axis := {}
var _last_input_ms := 0

var _hb_acc := 0.0
var _ping_sent_ms := 0
var _last_pong_ms := 0

var _join_ip := ""
var _join_port := Cfg.GAME_PORT
var _reconnecting := false
var _reconnect_left := 0
var _reconnect_wait := 0.0
var _resume_token := ""
var _resume_name := ""
var _reserved := {} # token -> {name, slot, until}
var _host_game_config: Dictionary = {}
var _room_emit_acc := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resume_name = "墨客·%03d" % (randi() % 1000)


func _process(delta: float) -> void:
	if discovery != null:
		discovery.poll(delta)
		if role == "" and discovery.is_active():
			_room_emit_acc += delta
			if _room_emit_acc >= 0.5:
				_room_emit_acc = 0.0
				rooms_changed.emit(discovery.rooms())
	_prune_reserved()
	_tick_heartbeat(delta)
	_tick_reconnect(delta)
	if role == "client" and state == "playing":
		_sample_input_edges()
		_pump_input(delta)


# ---------------------------------------------------------------- 房间 / 会话

## 主机开房：返回空串表示成功，否则为可展示的错误原因
func host_room(room_name: String, mode: String, difficulty: int, skull: String) -> String:
	teardown("", false)
	LocalCoop.ensure_input()
	role = "host"
	state = "hosting"
	local_slot = 0
	room = {
		"name": room_name.strip_edges() if room_name.strip_edges() != "" else "墨构 · 房主",
		"mode": mode, "difficulty": clampi(difficulty, 0, 4), "skull": skull,
		"max": Cfg.MAX_PLAYERS,
	}
	members = {1: {"name": str(room["name"]), "slot": 0, "ready": true, "token": "host"}}
	discovery = Discovery.new()
	if not discovery.start_host(Callable(self, "_beacon_info")):
		var why := discovery.error
		teardown("", false)
		return why
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(Cfg.GAME_PORT, Cfg.MAX_PLAYERS - 1)
	if err != OK:
		teardown("", false)
		return "创建房间失败：%s" % error_string(err)
	_peer = p
	multiplayer.multiplayer_peer = p
	_wire()
	state = "lobby"
	_emit_lobby()
	return ""


## 客户端加入：连接为异步，结果通过 joined / join_failed 信号返回
func join_room(ip: String, port := Cfg.GAME_PORT) -> String:
	teardown("", false)
	LocalCoop.ensure_input()
	_resume_token = ""
	role = "client"
	state = "joining"
	local_slot = 1
	_join_ip = ip.strip_edges()
	_join_port = port
	var err := _connect_client()
	if err != "":
		teardown("", true)
		return err
	_wire()
	return ""


## 大厅里开始对局（仅主机可调用）。成功后双方各自进入房间。
func start_game(mode: String, difficulty: int, skull: String) -> String:
	if role != "host":
		return "只有房主可以开始对局"
	if state != "lobby":
		return "当前状态不可开始"
	if members.size() < 2:
		return "需要至少一名队友加入后才能开始"
	room["mode"] = mode
	room["difficulty"] = clampi(difficulty, 0, 4)
	room["skull"] = skull
	_host_game_config = {"mode": mode, "difficulty": int(room["difficulty"]), "skull": skull}
	state = "playing"
	Run.net_role = "host"
	Run.net_slot = 0
	Run.start(mode, skull, int(room["difficulty"]), true)
	# 每个成员在自己的大厅里选的化身分别落到各自槽位，联机也能一人一角色
	for id in members:
		var m: Dictionary = members[id]
		var pick := str(m.get("skull", ""))
		if pick != "":
			Run.set_slot_skull(int(m.get("slot", 0)), pick)
	Run.set_net_players(members.size()) # start() 会重置人数，必须在开局后写入
	_rpc_game_start.rpc({"config": _host_game_config, "run": run_payload()})
	_emit_lobby()
	session_started.emit(_host_game_config)
	_go(ROOM_SCENE, "正在联机入卷")
	return ""


## 自己在大厅里选中的化身（主机取房间设置，客机取自己成员条目）
func my_skull() -> String:
	if role == "client":
		var m: Dictionary = members.get(multiplayer.get_unique_id(), {})
		return str(m.get("skull", ""))
	return str(room.get("skull", ""))


## 客机把选中的化身报给主机；开局时按槽位分配，互不覆盖
func set_my_skull(skull: String) -> void:
	if role != "client" or skull == "":
		return
	rpc_id(1, "_rpc_skull", skull)


## 客户端就绪状态
func set_ready(ready: bool) -> void:
	if role == "client":
		rpc_id(1, "_rpc_ready", ready)
	elif role == "host" and members.has(1):
		members[1]["ready"] = true
		_emit_lobby()


## 房主推进到下一张房间：先同步 Run，再双方各自切场景
func host_change_room() -> void:
	if role != "host":
		return
	_emit_event({"kind": "room_change", "run": run_payload()})
	_go(ROOM_SCENE, "正在入卷")


## 房主结束整局（结算/阵亡）：先让可靠事件发出，再关闭连接
func host_end_session(reason: String) -> void:
	_emit_event({"kind": "session_end", "reason": reason})
	await get_tree().create_timer(0.3).timeout
	teardown(reason, true)


## 主动离开（主机离开会通知客机回菜单）
func leave() -> void:
	if role == "host":
		_emit_event({"kind": "session_end", "reason": "房主已收起此卷"})
		await get_tree().create_timer(0.2).timeout
	elif role == "client":
		rpc_id(1, "_rpc_leave")
		await get_tree().create_timer(0.15).timeout
	teardown("已离开房间", true)


func teardown(reason := "", notify := false) -> void:
	_suppress_disconnect = true
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	_peer = null
	_suppress_disconnect = false
	if discovery != null:
		discovery.stop()
		discovery = null
	role = ""
	state = "idle"
	members.clear()
	room.clear()
	latest_snapshot.clear()
	snapshot_seq = 0
	_remote_held.clear()
	_remote_just.clear()
	_remote_just_at.clear()
	_remote_axis.clear()
	_reserved.clear()
	_reconnecting = false
	_reconnect_left = 0
	Run.net_role = ""
	Run.net_slot = 0
	if notify:
		session_ended.emit(reason)


## 复制当前 Run 的展示/结算字段，供客户端覆盖本地状态（客户端绝不调用 Run.start，避免随机分叉）
func run_payload() -> Dictionary:
	return {
		"mode": Run.mode,
		"difficulty": Run.difficulty,
		"depth": Run.depth,
		"room": Run.room_index,
		"skull": Run.skull_id,
		"upgrades": Run.upgrades.duplicate(true),
		"blessing": Run.blessing,
		"boss": Run.boss_id,
		"boss_queue": Run.boss_queue.duplicate(),
		"phase": Run.boss_phase,
		"hp": Run.hp,
		"max_hp": Run.max_hp,
		"max_hp_loss": Run.max_hp_loss,
		"red_butterfly": Run.c021_red_butterfly_used,
		"butterfly_cap": Run.c021_revive_cap,
		"blessing_used": Run.blessing_used,
		"supply_hp": Run.supply_hp,
		"supply_revive": Run.supply_revive,
		"supply_revive_used": Run.supply_revive_used,
		"guard": Run.guard_available,
		# 联机：人数决定敌方难度行；每槽血量与化身随房间切换一起下发
		"players": Run.player_count(),
		"net_slots": Run.slot_hp.duplicate(),
		"net_skulls": Run.slot_skull.duplicate(),
	}


# ---------------------------------------------------------------- 发现

func begin_scan() -> void:
	if role != "":
		return
	if discovery == null:
		discovery = Discovery.new()
	if not discovery.start_scan():
		net_notice.emit(discovery.error)
		discovery = null


func end_scan() -> void:
	if role == "" and discovery != null:
		discovery.stop()
		discovery = null


func discovered_rooms() -> Array:
	return discovery.rooms() if discovery != null else []


# ---------------------------------------------------------------- 远端输入（主机侧）

func is_remote_slot(slot: int) -> bool:
	return role == "host" and state == "playing" and slot > 0 and slot < Cfg.MAX_PLAYERS


func remote_held(slot: int, action: String) -> bool:
	return bool(_remote_held.get(slot, {}).get(action, false))


## 读取即消费，带 200ms 过期，避免丢帧时残留“幽灵按键”
func take_remote_just(slot: int, action: String) -> bool:
	var just: Dictionary = _remote_just.get(slot, {})
	if not just.has(action):
		return false
	var at: Dictionary = _remote_just_at.get(slot, {})
	var now := Time.get_ticks_msec()
	if now - int(at.get(action, 0)) > 200:
		just.erase(action)
		at.erase(action)
		return false
	just.erase(action)
	at.erase(action)
	return true


func remote_axis(slot: int) -> int:
	return int(_remote_axis.get(slot, 0))


func remote_link_age_ms() -> int:
	return Time.get_ticks_msec() - _last_input_ms if _last_input_ms > 0 else -1


# ---------------------------------------------------------------- 快照

func push_snapshot(payload: Dictionary) -> void:
	if role != "host" or state != "playing":
		return
	if multiplayer.multiplayer_peer == null:
		return
	snapshot_seq += 1
	if snapshot_seq > 0xFFFFFFF0:
		snapshot_seq = 1
	var data := payload.duplicate(true)
	data["seq"] = snapshot_seq
	var bytes := Proto.pack(Proto.T_SNAPSHOT, snapshot_seq, data)
	_rpc_snapshot.rpc(bytes)


# ---------------------------------------------------------------- RPC：连接

@rpc("any_peer", "call_remote", "reliable", Cfg.CH_CONTROL)
func _rpc_join(d: Dictionary) -> void:
	if role != "host" or state == "idle":
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	if str(d.get("app", "")) != Cfg.APP_ID or int(d.get("v", 0)) != Cfg.PROTO_VERSION:
		_rpc_join_result.rpc_id(sender, {"ok": false, "reason": "版本不一致，请更新到同一版本"})
		return
	var token := str(d.get("token", ""))
	var resumed := false
	var slot := -1
	if token != "" and _reserved.has(token):
		var r: Dictionary = _reserved[token]
		if Time.get_ticks_msec() <= int(r.get("until", 0)):
			resumed = true
			slot = int(r.get("slot", 1))
		_reserved.erase(token)
	if not resumed:
		slot = _free_slot()
		if slot < 0:
			_rpc_join_result.rpc_id(sender, {"ok": false, "reason": "房间已满（最多 4 人）"})
			return
	if token == "" or not resumed:
		token = _make_token()
	var name := str(d.get("name", "墨客")).substr(0, 16)
	members[sender] = {"name": name, "slot": slot, "ready": false, "token": token, "skull": ""}
	# 开局后中途加入/重连：人数立即影响后续波次的难度行
	if state == "playing":
		Run.set_net_players(members.size())
	_rpc_join_result.rpc_id(sender, {
		"ok": true, "slot": slot, "token": token, "resumed": resumed,
		"state": state, "room": room.duplicate(true), "game": _host_game_config.duplicate(true),
		"run": run_payload() if state == "playing" else {},
	})
	_emit_lobby()


@rpc("authority", "call_remote", "reliable", Cfg.CH_CONTROL)
func _rpc_join_result(d: Dictionary) -> void:
	if role != "client":
		return
	if not bool(d.get("ok", false)):
		var why := str(d.get("reason", "加入失败"))
		_suppress_disconnect = true
		multiplayer.multiplayer_peer = null
		_peer = null
		_suppress_disconnect = false
		role = ""
		state = "idle"
		_reconnecting = false
		join_failed.emit(why)
		return
	_resume_token = str(d.get("token", ""))
	local_slot = int(d.get("slot", 1))
	var resumed := bool(d.get("resumed", false))
	state = str(d.get("state", "lobby"))
	_host_game_config = d.get("game", {}) if d.get("game", {}) is Dictionary else {}
	_last_pong_ms = Time.get_ticks_msec()
	_reconnecting = false
	_reconnect_left = 0
	joined.emit(resumed)
	if resumed:
		link_restored.emit()
	if state == "playing":
		_apply_run_sync(d.get("run", {}) if d.get("run", {}) is Dictionary else {})
		session_started.emit(_host_game_config)
		if auto_enter_room:
			_go(ROOM_SCENE, "正在联机入卷")


@rpc("any_peer", "call_remote", "reliable", Cfg.CH_CONTROL)
func _rpc_leave() -> void:
	if role != "host":
		return
	var sender := multiplayer.get_remote_sender_id()
	if members.has(sender):
		var left_slot := int(members[sender].get("slot", -1))
		members.erase(sender)
		_remote_held.erase(left_slot)
		_remote_just.erase(left_slot)
		_remote_just_at.erase(left_slot)
		_remote_axis.erase(left_slot)
		if state == "playing":
			# 有人主动离开：本房保留其倒地，且下一房不再复活该席位
			Run.slot_revive.erase(left_slot)
			Run.slot_dead[left_slot] = true
			Run.set_net_players(members.size())
	_emit_lobby()
	_emit_event({"kind": "notice", "text": "队友已离开房间"})
	if _peer != null:
		_peer.disconnect_peer(sender)


@rpc("any_peer", "call_remote", "reliable", Cfg.CH_CONTROL)
func _rpc_ready(value: bool) -> void:
	if role != "host":
		return
	var sender := multiplayer.get_remote_sender_id()
	if members.has(sender):
		members[sender]["ready"] = value
		_emit_lobby()


## 客机上报自己选的化身；主机记账并在开局时按槽位分配
@rpc("any_peer", "call_remote", "reliable", Cfg.CH_CONTROL)
func _rpc_skull(skull: String) -> void:
	if role != "host" or not Skulls.ids().has(skull):
		return
	var sender := multiplayer.get_remote_sender_id()
	if members.has(sender):
		members[sender]["skull"] = skull
		_emit_lobby()


@rpc("authority", "call_remote", "reliable", Cfg.CH_CONTROL)
func _rpc_game_start(data: Dictionary) -> void:
	if role != "client":
		return
	var cfg = data.get("config", {})
	_host_game_config = cfg if cfg is Dictionary else {}
	state = "playing"
	_apply_run_sync(data.get("run", {}) if data.get("run", {}) is Dictionary else {})
	session_started.emit(_host_game_config)
	if auto_enter_room:
		_go(ROOM_SCENE, "正在联机入卷")


@rpc("authority", "call_remote", "reliable", Cfg.CH_CONTROL)
func _rpc_lobby(data: Dictionary) -> void:
	if role != "client":
		return
	room = data.get("room", {}) if data.get("room", {}) is Dictionary else {}
	var rows: Array = data.get("members", []) if data.get("members", []) is Array else []
	members.clear()
	for row in rows:
		if row is Dictionary:
			members[int(row.get("id", 0))] = row
	lobby_changed.emit(data)


@rpc("authority", "call_remote", "reliable", Cfg.CH_CONTROL)
func _rpc_event(ev: Dictionary) -> void:
	if role != "client":
		return
	match str(ev.get("kind", "")):
		"room_change":
			_apply_run_sync(ev.get("run", {}) if ev.get("run", {}) is Dictionary else {})
			_go(ROOM_SCENE, "正在入卷")
		"session_end":
			var reason := str(ev.get("reason", "对局已结束"))
			teardown(reason, true)
			_go(MENU_SCENE, "正在收卷")
		"notice":
			net_notice.emit(str(ev.get("text", "")))


# ---------------------------------------------------------------- RPC：心跳与输入

@rpc("any_peer", "call_remote", "unreliable_ordered", Cfg.CH_INPUT)
func _rpc_ping(stamp: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender > 0:
		_rpc_pong.rpc_id(sender, stamp)


@rpc("authority", "call_remote", "unreliable_ordered", Cfg.CH_INPUT)
func _rpc_pong(stamp: int) -> void:
	if role != "client":
		return
	_last_pong_ms = Time.get_ticks_msec()
	last_rtt_ms = maxi(0, _last_pong_ms - stamp)


@rpc("any_peer", "call_remote", "unreliable_ordered", Cfg.CH_INPUT)
func _rpc_input(bytes: PackedByteArray) -> void:
	if role != "host" or state != "playing":
		return
	var d := Proto.unpack(bytes)
	if d.is_empty() or int(d.get("_type", 0)) != Proto.T_INPUT:
		bad_packets += 1
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0 or not members.has(sender):
		return
	var slot := int(members[sender].get("slot", -1))
	if slot <= 0 or slot >= Cfg.MAX_PLAYERS:
		return
	var clean := Proto.sanitize_input(d)
	_last_input_ms = Time.get_ticks_msec()
	var held := {}
	for a in clean["held"]:
		held[str(a)] = true
	var axis := int(clean["axis"])
	if axis < 0:
		held["move_left"] = true
	elif axis > 0:
		held["move_right"] = true
	_remote_held[slot] = held
	_remote_axis[slot] = axis
	var just: Dictionary = _remote_just.get(slot, {})
	var at: Dictionary = _remote_just_at.get(slot, {})
	for a in clean["just"]:
		var name := str(a)
		just[name] = true
		at[name] = _last_input_ms
	_remote_just[slot] = just
	_remote_just_at[slot] = at


@rpc("authority", "call_remote", "unreliable_ordered", Cfg.CH_SNAPSHOT)
func _rpc_snapshot(bytes: PackedByteArray) -> void:
	if role != "client":
		return
	var d := Proto.unpack(bytes)
	if d.is_empty() or int(d.get("_type", 0)) != Proto.T_SNAPSHOT:
		bad_packets += 1
		return
	var seq := int(d.get("_seq", 0))
	if seq <= snapshot_seq:
		return
	snapshot_seq = seq
	latest_snapshot = Proto.sanitize_snapshot(d)


# ---------------------------------------------------------------- 连接事件

func _wire() -> void:
	if _mp_wired:
		return
	_mp_wired = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _connect_client() -> String:
	# 丢弃上一次失败的连接尝试，避免旧连接迟到的信号干扰新连接
	if _peer != null:
		_peer.close()
		_peer = null
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(_join_ip, _join_port)
	if err != OK:
		return "无法连接 %s:%d（%s）" % [_join_ip, _join_port, error_string(err)]
	_peer = p
	multiplayer.multiplayer_peer = p
	_last_pong_ms = Time.get_ticks_msec()
	return ""


func _on_connected_to_server() -> void:
	rpc_id(1, "_rpc_join", {
		"app": Cfg.APP_ID, "v": Cfg.PROTO_VERSION,
		"name": _resume_name, "token": _resume_token,
	})


func _on_connection_failed() -> void:
	if role != "client":
		return
	# 已经连上（或已在局内）说明这是被替换掉的旧连接尝试迟到的失败，不能打断当前链路
	if state == "playing" or state == "lobby":
		return
	if _reconnecting:
		return # 交给重连节拍继续重试
	if _resume_token != "":
		_begin_reconnect("连接中断，正在重连…")
		return
	_suppress_disconnect = true
	multiplayer.multiplayer_peer = null
	_peer = null
	_suppress_disconnect = false
	role = ""
	state = "idle"
	join_failed.emit("无法连接到主机（请确认在同一局域网、主机已开房）")


func _on_server_disconnected() -> void:
	if role != "client" or _suppress_disconnect:
		return
	if _resume_token != "" or state == "playing" or state == "lobby":
		_begin_reconnect("与主机断开，正在重连…")
		return
	teardown("与主机断开", true)


func _on_peer_connected(_id: int) -> void:
	net_notice.emit("有玩家正在加入…")


func _on_peer_disconnected(id: int) -> void:
	if role != "host" or _suppress_disconnect:
		return
	if not members.has(id):
		return
	var m: Dictionary = members[id]
	members.erase(id)
	var gone_slot := int(m.get("slot", 1))
	_remote_held.erase(gone_slot)
	_remote_just.erase(gone_slot)
	_remote_just_at.erase(gone_slot)
	_remote_axis.erase(gone_slot)
	if state == "playing":
		Run.set_net_players(members.size())
		Run.slot_revive.erase(gone_slot)
		Run.slot_dead[gone_slot] = true
		_reserved[str(m.get("token", ""))] = {
			"name": m.get("name", "队友"), "slot": m.get("slot", 1),
			"until": Time.get_ticks_msec() + int(Cfg.RECONNECT_GRACE * 1000.0),
		}
		net_notice.emit("队友已断开，保留席位 %d 秒等待重连" % int(Cfg.RECONNECT_GRACE))
	else:
		_emit_lobby()


# ---------------------------------------------------------------- 内部节拍

func _sample_input_edges() -> void:
	for a in Cfg.ACTIONS:
		if Input.is_action_just_pressed(LocalCoop.action(1, a)):
			_pending_just[str(a)] = true


func _pump_input(delta: float) -> void:
	_input_acc += delta
	if _input_acc < 1.0 / Cfg.INPUT_HZ:
		return
	_input_acc = 0.0
	if multiplayer.multiplayer_peer == null:
		return
	var held: Array = []
	for a in Cfg.ACTIONS:
		if Input.is_action_pressed(LocalCoop.action(1, a)):
			held.append(a)
	var axis := 0
	if Input.is_action_pressed(LocalCoop.action(1, "move_left")):
		axis -= 1
	if Input.is_action_pressed(LocalCoop.action(1, "move_right")):
		axis += 1
	var just: Array = _pending_just.keys()
	_pending_just.clear()
	_input_seq += 1
	var payload := {"seq": _input_seq, "axis": axis, "held": held, "just": just}
	rpc_id(1, "_rpc_input", Proto.pack(Proto.T_INPUT, _input_seq, payload))


func _tick_heartbeat(delta: float) -> void:
	if role != "client" or (state != "playing" and state != "lobby"):
		return
	_hb_acc += delta
	var now := Time.get_ticks_msec()
	if _hb_acc >= Cfg.HEARTBEAT_INTERVAL:
		_hb_acc = 0.0
		_ping_sent_ms = now
		rpc_id(1, "_rpc_ping", now)
	# 刚入房/重连后的宽限期内不判超时
	if now - _last_pong_ms > int(Cfg.HEARTBEAT_TIMEOUT * 1000.0) and _resume_token != "":
		_begin_reconnect("与主机失联，正在重连…")


func _tick_reconnect(delta: float) -> void:
	if not _reconnecting:
		return
	_reconnect_wait -= delta
	if _reconnect_wait > 0.0:
		return
	if _reconnect_left <= 0:
		_reconnecting = false
		var why := "重连失败，已退出房间"
		teardown(why, false)
		join_failed.emit(why)
		return
	_reconnect_left -= 1
	_reconnect_wait = Cfg.RECONNECT_DELAY
	state = "reconnecting"
	var err := _connect_client()
	if err != "":
		net_notice.emit(err)


func _begin_reconnect(reason: String) -> void:
	if role != "client" or _reconnecting:
		return
	_reconnecting = true
	_reconnect_left = Cfg.RECONNECT_TRIES
	_reconnect_wait = 0.0
	_suppress_disconnect = true
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	_peer = null
	_suppress_disconnect = false
	state = "reconnecting"
	link_lost.emit(reason)


func _prune_reserved() -> void:
	if _reserved.is_empty():
		return
	var now := Time.get_ticks_msec()
	for token in _reserved.keys():
		if now > int(_reserved[token].get("until", 0)):
			_reserved.erase(token)
			net_notice.emit("队友重连超时，席位已释放")


# ---------------------------------------------------------------- 工具

func _emit_lobby() -> void:
	var rows: Array = []
	for id in members:
		var m: Dictionary = members[id]
		rows.append({
			"id": id, "name": m.get("name", "墨客"), "slot": int(m.get("slot", 0)),
			"ready": bool(m.get("ready", false)), "host": int(id) == 1,
			"skull": str(m.get("skull", "")),
		})
	var data := {"room": room.duplicate(true), "members": rows, "state": state}
	lobby_changed.emit(data)
	if role == "host" and multiplayer.multiplayer_peer != null:
		_rpc_lobby.rpc(data)


func _emit_event(ev: Dictionary) -> void:
	if role == "host" and multiplayer.multiplayer_peer != null:
		_rpc_event.rpc(ev)


## 分配一个空槽位（1~MAX_PLAYERS-1），同时尊重断线保留中的席位；满了返回 -1。
func _free_slot() -> int:
	var used := {}
	for id in members:
		used[int(members[id].get("slot", -1))] = true
	for r in _reserved.values():
		used[int(r.get("slot", -1))] = true
	for slot in range(1, Cfg.MAX_PLAYERS):
		if not used.has(slot):
			return slot
	return -1


func _client_peer() -> int:
	if role != "host" or multiplayer.multiplayer_peer == null:
		return 0
	for id in members:
		if int(id) != 1:
			return int(id)
	return 0


func _make_token() -> String:
	return "%08x%04x" % [Time.get_ticks_usec() & 0xFFFFFFFF, randi() & 0xFFFF]


func _beacon_info() -> Dictionary:
	return {
		"app": Cfg.APP_ID, "v": Cfg.PROTO_VERSION,
		"name": str(room.get("name", "墨构 · 房主")),
		"port": Cfg.GAME_PORT,
		"players": members.size(),
		"max": Cfg.MAX_PLAYERS,
		"mode": str(room.get("mode", "adventure")),
		"difficulty": int(room.get("difficulty", 1)),
		"skull": str(room.get("skull", "")),
		"state": state,
	}


## 客户端用主机下发的 Run 状态覆盖本地（不调用 Run.start，避免 Boss/随机数分叉）
func _apply_run_sync(d: Dictionary) -> void:
	Run.active = true
	Run.local_coop = true
	Run.net_role = "client"
	Run.net_slot = local_slot
	if d.is_empty():
		return
	Run.mode = str(d.get("mode", Run.mode))
	Run.difficulty = clampi(int(d.get("difficulty", Run.difficulty)), 0, 4)
	Run.depth = maxi(1, int(d.get("depth", Run.depth)))
	Run.room_index = maxi(0, int(d.get("room", Run.room_index)))
	Run.skull_id = str(d.get("skull", Run.skull_id))
	var up = d.get("upgrades", {})
	Run.upgrades = (up as Dictionary).duplicate(true) if up is Dictionary else {}
	Run.blessing = str(d.get("blessing", ""))
	Run.boss_id = str(d.get("boss", ""))
	var queue = d.get("boss_queue", [])
	Run.boss_queue = (queue as Array).duplicate() if queue is Array else []
	Run.boss_phase = int(d.get("phase", 0))
	Run.max_hp = maxi(1, int(d.get("max_hp", Run.max_hp)))
	Run.hp = clampi(int(d.get("hp", Run.hp)), 1, Run.max_hp)
	Run.max_hp_loss = int(d.get("max_hp_loss", 0))
	Run.c021_red_butterfly_used = bool(d.get("red_butterfly", false))
	Run.c021_revive_cap = int(d.get("butterfly_cap", 0))
	Run.blessing_used = bool(d.get("blessing_used", false))
	Run.supply_hp = int(d.get("supply_hp", 0))
	Run.supply_revive = bool(d.get("supply_revive", false))
	Run.supply_revive_used = bool(d.get("supply_revive_used", false))
	Run.guard_available = bool(d.get("guard", false))
	Run.set_net_players(int(d.get("players", 2)))
	var slots = d.get("net_slots", {})
	Run.slot_hp = (slots as Dictionary).duplicate() if slots is Dictionary else {}
	var skulls = d.get("net_skulls", {})
	if skulls is Dictionary and not (skulls as Dictionary).is_empty():
		Run.slot_skull = (skulls as Dictionary).duplicate()
	Run.slot_dead.clear()
	Run.slot_revive.clear()


func _go(path: String, veil_text: String) -> void:
	if not auto_enter_room or _transitioning:
		return
	_transitioning = true
	await LoadVeil.transition_to(path, veil_text)
	_transitioning = false
