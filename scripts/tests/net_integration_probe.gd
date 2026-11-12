extends Node

## 联机集成测试探针（双进程）：主机 / 客机各跑一份，验证真实 ENet 连接下的
## 建房 -> 发现后加入（此处用手动回环地址）-> 就绪 -> 开局 -> 输入上送 -> 快照下发
## -> 坏包拒绝 -> 断线重连 的完整链路。
## 主机：godot --headless --path . res://scenes/tests/net_integration_probe.tscn -- --role=host
## 客机：godot --headless --path . res://scenes/tests/net_integration_probe.tscn -- --role=client

const Cfg = preload("res://scripts/net/net_config.gd")
const Proto = preload("res://scripts/net/net_protocol.gd")

var role := ""
var fail := 0
var t := 0.0

# 主机侧
var started := false
var snap_acc := 0.0
var snap_n := 0
var saw_remote := false
var saw_bad := false
var prev_members := 0
var saw_drop := false
var saw_rejoin := false
var play_t := 0.0
var sent_settlement := false

# 客机侧
var c_play := 0.0
var input_acc := 0.0
var input_seq := 0
var sent_bad := false
var ps_ok := false
var es_ok := false
var closed_peer := false
var was_reconnecting := false
var pre_disconnect_seq := 0
var reconnect_ok := false
var settlement_ok := false
var finished := false


func _ready() -> void:
	role = _role()
	LanNet.auto_enter_room = false
	print("PROBE ROLE %s" % role)
	if role == "host":
		LanNet.lobby_changed.connect(_on_lobby)
		var err := LanNet.host_room("集成测试房", Run.MODE_ADVENTURE, 1, "c021")
		_check("host_create_room", err == "", err)
	else:
		LanNet.joined.connect(_on_joined)
		LanNet.join_failed.connect(_on_join_failed)
		LanNet.session_started.connect(_on_session_started)
		LanNet.settlement.connect(_on_settlement)
		var err2 := LanNet.join_room("127.0.0.1")
		_check("client_join_call", err2 == "", err2)


func _process(delta: float) -> void:
	t += delta
	if role == "host":
		_tick_host(delta)
	else:
		_tick_client(delta)


# ---------------------------------------------------------------- 主机

func _on_lobby(_data: Dictionary) -> void:
	if role == "host" and not started and LanNet.state == "lobby" and LanNet.members.size() >= 2:
		started = true
		prev_members = LanNet.members.size()
		var err := LanNet.start_game(Run.MODE_ADVENTURE, 1, "c021")
		_check("host_start_game", err == "", err)


func _tick_host(delta: float) -> void:
	if not started or LanNet.state != "playing":
		return
	play_t += delta
	snap_acc += delta
	if snap_acc >= 1.0 / Cfg.SNAPSHOT_HZ:
		snap_acc = 0.0
		_push_snapshot()
	# 结算事件传输：客机应在断开重连前收到完整战绩
	if play_t > 0.8 and not sent_settlement:
		sent_settlement = true
		LanNet.host_settlement({
			"title": "集成结算", "cleared": true, "roster": [], "last_slot": -1,
			"kills": 7, "max_combo": 5, "last_hit": {}, "boss_defeated": [],
		})
	if LanNet.remote_held(1, "attack") or LanNet.remote_axis(1) != 0:
		saw_remote = true
	if LanNet.bad_packets > 0:
		saw_bad = true
	var n := LanNet.members.size()
	if n < prev_members:
		saw_drop = true
	elif n > prev_members and saw_drop:
		saw_rejoin = true
	prev_members = n

	if play_t > 24.0 or (reconnect_seen() and play_t > 12.0):
		_check("host_remote_input", saw_remote)
		_check("host_bad_packet_rejected", saw_bad)
		_check("host_snapshot_sent", snap_n > 20, "n=%d" % snap_n)
		_check("host_client_dropped", saw_drop)
		_check("host_client_rejoined", saw_rejoin)
		_done()


func reconnect_seen() -> bool:
	return saw_drop and saw_rejoin


func _push_snapshot() -> void:
	LanNet.push_snapshot({
		"ps": [
			[0, 120.0, 120.0, 8, 8, 0, 1, "stand", true, false, false],
			[1, 150.0, 120.0, 8, 8, 0, 1, "stand", true, false, false],
		],
		"es": [[1, "res://scenes/enemies/c016.tscn", 0, 300.0, 300.0, 4, 4, 0, 1, "stand", true]],
		"run": LanNet.run_payload(),
	})
	snap_n += 1


# ---------------------------------------------------------------- 客机

func _on_joined(resumed: bool) -> void:
	_check("client_joined", true, "resumed=%s" % str(resumed))
	LanNet.set_ready(true)


func _on_join_failed(reason: String) -> void:
	# 断线重连阶段的失败由 LanNet 的重连节拍继续重试，不算整体失败
	if closed_peer:
		return
	_check("client_joined", false, reason)


func _on_session_started(_cfg: Dictionary) -> void:
	pass


func _on_settlement(d: Dictionary) -> void:
	settlement_ok = str(d.get("title", "")) == "集成结算" and int(d.get("kills", -1)) == 7


func _tick_client(delta: float) -> void:
	if LanNet.state == "playing":
		c_play += delta
		if c_play < 2.0:
			input_acc += delta
			if input_acc >= 1.0 / Cfg.INPUT_HZ:
				input_acc = 0.0
				input_seq += 1
				LanNet.rpc_id(1, "_rpc_input", Proto.pack(Proto.T_INPUT, input_seq, {
					"seq": input_seq, "axis": 1,
					"held": ["attack", "move_right"], "just": ["attack"],
				}))
		if LanNet.snapshot_seq > 0:
			var snap: Dictionary = LanNet.latest_snapshot
			if (snap.get("ps", []) as Array).size() == 2:
				ps_ok = true
			if (snap.get("es", []) as Array).size() == 1:
				es_ok = true
		if c_play > 0.5 and not sent_bad:
			sent_bad = true
			# 故意截断的坏包：主机应记入 bad_packets 并丢弃
			LanNet.rpc_id(1, "_rpc_input", PackedByteArray([0x49, 0x01]))
		if c_play > 2.5 and not closed_peer:
			closed_peer = true
			pre_disconnect_seq = LanNet.snapshot_seq
			if LanNet.multiplayer.multiplayer_peer != null:
				LanNet.multiplayer.multiplayer_peer.close()
	# 断线重连由 LanNet 的断线回调与心跳自动触发，这里只观察状态与序号是否恢复
	if LanNet.state == "reconnecting":
		was_reconnecting = true
	if closed_peer and was_reconnecting and LanNet.state == "playing" and LanNet.snapshot_seq > pre_disconnect_seq:
		reconnect_ok = true

	if (reconnect_ok and ps_ok and es_ok) or c_play > 20.0 or t > 35.0:
		_check("client_snapshot_players", ps_ok)
		_check("client_snapshot_enemies", es_ok)
		_check("client_snapshot_seq", LanNet.snapshot_seq > 0, "seq=%d" % LanNet.snapshot_seq)
		_check("client_settlement", settlement_ok)
		_check("client_reconnect", reconnect_ok)
		LanNet.leave()
		_done()


# ---------------------------------------------------------------- 工具

func _role() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			return a.substr(7)
	return "host"


func _check(name: String, cond: bool, detail := "") -> void:
	print("PROBE %s %s%s" % [name, "PASS" if cond else "FAIL", (" " + detail) if detail != "" else ""])
	if not cond:
		fail += 1


func _done() -> void:
	if finished or not is_inside_tree():
		return
	finished = true
	set_process(false)
	print("PROBE RESULT fail=%d" % fail)
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(1 if fail > 0 else 0)
