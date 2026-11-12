extends Node

## 双进程联机结算回归：主机开局后双方各自实例化真实 room_01（不切场景），
## 主机触发通关结算，验证客机能弹出结算面板、同步战绩、本地领奖，
## 且主机结束会话后客机不会被强制踢回主菜单。
##
## 主机：godot --headless --path . res://scenes/tests/coop_room_probe.tscn -- --role=host
## 客机：godot --headless --path . res://scenes/tests/coop_room_probe.tscn -- --role=client

const ROOM_SCENE := "res://scenes/world/room_01.tscn"
const SpineFX := preload("res://scripts/systems/spine_fx.gd")

var role := ""
var fail := 0
var finished := false
var t := 0.0

var started := false
var room = null
var settlement_sent := false
var session_ended := false
var settlement_seen := false
var panel_ok := false
var reward_ok := false
var fx_ok := false
var mastery_before := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	role = _arg("--role=", "host")
	LanNet.auto_enter_room = false
	LanNet.settlement.connect(_on_settlement)
	if role == "host":
		LanNet.lobby_changed.connect(_on_lobby)
		var err := LanNet.host_room("结算回归房", Run.MODE_ADVENTURE, 1, "c021")
		_check("host_create_room", err == "", err)
	else:
		LanNet.my_pick = "c021"
		mastery_before = Meta.mastery_exp("c021")
		LanNet.session_started.connect(_on_session_started)
		var err := LanNet.join_room("127.0.0.1")
		_check("client_join_call", err == "", err)


func _process(delta: float) -> void:
	t += delta
	if finished:
		return
	if t > 20.0:
		_check("no_timeout", false, "role=%s state=%s room=%s" % [role, LanNet.state, str(room != null)])
		_done()
		return
	if role == "client":
		_tick_client()


func _on_lobby(_data: Dictionary) -> void:
	if role != "host" or started:
		return
	if LanNet.state != "lobby" or LanNet.members.size() < 2:
		return
	started = true
	Score.kills = 7
	Score.max_combo = 5
	var err := LanNet.start_game(Run.MODE_ADVENTURE, 1, "c021")
	_check("host_start_game", err == "", err)
	_make_room()
	_check("host_fx_hook", SpineFX.net_hook.is_valid())
	# 客机建好房间后会重新置 ready：等它就绪再发特效，避免时序竞争造成误判
	await _wait_client_ready()
	if finished:
		return
	await get_tree().create_timer(1.0, true).timeout
	if finished:
		return
	# 主机生成一个战场内世界特效：客机应在下一帧快照里回放出来
	if is_instance_valid(room):
		var fx_node = SpineFX.spawn(room, "E21013", Vector2(320, 500), {"anim": "win", "scale": 0.3})
		_check("host_fx_spawned", fx_node != null)
		var ns = room.get_node_or_null("NetSync")
		_check("host_fx_queued", ns != null and ns._fx_queue.size() > 0)
	await get_tree().create_timer(1.0, true).timeout
	if finished:
		return
	_trigger_settlement()
	await get_tree().create_timer(1.5, true).timeout
	if finished:
		return
	# 主机结束会话：客机应留在结算页，而不是被强制回主菜单
	await LanNet.host_end_session("对局结束")
	session_ended = true
	await get_tree().create_timer(0.6, true).timeout
	var panel = room.get_node_or_null("Settlement") if room != null else null
	var ns = room.get_node_or_null("NetSync") if room != null else null
	_check("host_fx_sent", ns != null and ns.fx_sent > 0, str(ns.fx_sent if ns != null else -1))
	_check("host_panel", panel != null)
	_check("host_panel_flag", panel != null and bool(panel._net_host))
	_done()


func _on_session_started(_cfg: Dictionary) -> void:
	_make_room()
	# 房间与 NetSync 已建好，通知主机可以开始发特效/结算
	LanNet.set_ready(true)


func _on_settlement(d: Dictionary) -> void:
	settlement_seen = str(d.get("title", "")) == "通  关" and int(d.get("kills", -1)) == 7


func _make_room() -> void:
	if room != null:
		return
	room = load(ROOM_SCENE).instantiate()
	room.name = "RoomCopy"
	add_child(room)


## 等所有客机把 ready 重新置真（客机在房间建好后才会置真）。
func _wait_client_ready() -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline and not finished:
		var all_ready := LanNet.members.size() >= 2
		for id in LanNet.members:
			if int(id) == 1:
				continue
			if not bool(LanNet.members[id].get("ready", false)):
				all_ready = false
				break
		if all_ready:
			_check("host_client_room_ready", true)
			return
		await get_tree().create_timer(0.1, true).timeout
	_check("host_client_room_ready", false)


func _trigger_settlement() -> void:
	if room == null or settlement_sent:
		return
	settlement_sent = true
	Score.kills = 7
	Score.max_combo = 5
	room._show_settlement("通  关", true)


func _tick_client() -> void:
	if room == null:
		return
	if not fx_ok:
		for n in room.get_children():
			if str(n.get_meta("net_fx", "")) == "E21013":
				fx_ok = true
				break
	var panel = room.get_node_or_null("Settlement")
	if panel != null and not panel_ok:
		panel_ok = true
		_check("client_panel", bool(panel._net_client))
		_check("client_settlement_seen", settlement_seen)
		_check("client_kills_synced", Score.kills == 7, str(Score.kills))
		_check("client_bad_packets", LanNet.bad_packets == 0, str(LanNet.bad_packets))
		var ns = room.get_node_or_null("NetSync")
		_check("client_fx_packet", LanNet.fx_received > 0, str(LanNet.fx_received))
		_check("client_fx_recv", ns != null and ns.fx_recv > 0, str(ns.fx_recv if ns != null else -1))
		_check("client_fx_replay", fx_ok, "seq=%d children=%d" % [LanNet.snapshot_seq, room.get_child_count()])
		reward_ok = Meta.mastery_exp("c021") >= mastery_before + 20
		_check("client_reward", reward_ok, "%d -> %d" % [mastery_before, Meta.mastery_exp("c021")])
	# 会话已结束且面板仍在：证明客机没有被 session_end 踢回主菜单
	if panel_ok and LanNet.state == "idle" and not session_ended:
		session_ended = true
		_check("client_kept_settlement", room.get_node_or_null("Settlement") != null)
		_done()


func _arg(prefix: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(prefix):
			return str(a).substr(prefix.length())
	return fallback


func _check(name: String, cond: bool, detail := "") -> void:
	print("PROBE %s %s%s" % [name, "PASS" if cond else "FAIL", (" " + detail) if detail != "" else ""])
	if not cond:
		fail += 1


func _done() -> void:
	if finished or not is_inside_tree():
		return
	finished = true
	set_process(false)
	print("PROBE RESULT role=%s fail=%d" % [role, fail])
	await get_tree().create_timer(0.3, true).timeout
	get_tree().quit(1 if fail > 0 else 0)
