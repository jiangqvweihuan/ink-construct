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
## 开局祝福 / 通关强化的三选一请求：payload = {kind, token, cards, slot}
## 房主与客机都会收到（房主收到的是自己那组），房间据此弹出本机面板。
signal choice_requested(payload: Dictionary)
## 主机确认所有人的选择都已落盘（客机据此关闭等待态并应用同步后的 Run）。
signal choice_resolved(kind: String)
## 主机结算数据：客机据此弹出与主机一致的结算面板并领取本地奖励。
signal settlement(data: Dictionary)

const Cfg = preload("res://scripts/net/net_config.gd")
const Proto = preload("res://scripts/net/net_protocol.gd")
const Discovery = preload("res://scripts/net/lan_discovery.gd")
const LocalCoop = preload("res://scripts/systems/local_coop.gd")
const Skulls = preload("res://scripts/player/skulls.gd")

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const ROOM_SCENE := "res://scenes/world/room_01.tscn"
const PVP_SCENE := "res://scenes/pvp/pvp_arena.tscn"

var role := "" # "" / "host" / "client"
var state := "idle" # idle / hosting / joining / lobby / playing / reconnecting
var room: Dictionary = {}
var members: Dictionary = {} # peer_id -> {name, slot, ready, token}
var local_slot := 0
var auto_enter_room := true # 测试关闭，避免测试进程加载整张房间
var latest_snapshot: Dictionary = {}
var pending_fx: Array = [] # 客机：已收到但尚未回放的特效事件（可靠通道下发，独立累积）
var fx_received := 0 # 诊断/测试：网络层收到的特效事件数
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
var _input_flush := false # 本次采样出现了新的按下边沿：立即上送，不再等 30Hz 节拍
## 远端输入按 slot 分桶（slot 1~3）；每个元素结构：{action: true} / {action: 毫秒时间戳}
var _remote_held := {}
var _remote_just := {}
var _remote_just_at := {}
var _remote_axis := {}
var _last_input_ms := 0

## 本机玩家选定的化身：离开房间 / 房间重置后仍保留，重进时自动上报。
var my_pick := ""
## 三选一（祝福 / 通关强化）的联机状态；主机权威，客机只提交自己的选择。
var _choice_kind := ""
var _choice_seq := 0
var _choice_open := false
var _choice_elapsed := 0.0
var _choice_cards := {} # slot -> Array[String]
var _choice_done := {} # slot -> key
var _pending_choice: Dictionary = {} # 客机：房间场景就绪前收到的请求先缓冲
var _pending_settlement: Dictionary = {} # 客机：房间场景就绪前收到的结算数据先缓冲

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
	_tick_choice(delta)
	if role == "client" and state == "playing":
		_sample_input_edges()
		if _input_flush:
			_input_flush = false
			_pump_input(delta, true)
		else:
			_pump_input(delta)


# ---------------------------------------------------------------- 房间 / 会话

## 主机开房：返回空串表示成功，否则为可展示的错误原因
func host_room(room_name: String, mode: String, difficulty: int, skull: String) -> String:
	teardown("", false)
	LocalCoop.ensure_input()
	role = "host"
	state = "hosting"
	local_slot = 0
	if skull == "":
		skull = my_pick if my_pick != "" else _default_pick()
	my_pick = skull
	room = {
		"name": room_name.strip_edges() if room_name.strip_edges() != "" else "墨构 · 房主",
		"mode": mode, "difficulty": clampi(difficulty, 0, 4), "skull": skull,
		"max": 2 if mode == Run.MODE_PVP else Cfg.MAX_PLAYERS,
	}
	# 房主自己也要在成员表里带上化身，大厅成员行与开局校验都按这张表读
	members = {1: {"name": str(room["name"]), "slot": 0, "ready": true, "token": "host", "skull": skull}}
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
	var is_pvp := mode == Run.MODE_PVP
	if is_pvp and members.size() != 2:
		return "对战模式需要恰好 2 名玩家"
	room["mode"] = mode
	room["difficulty"] = clampi(difficulty, 0, 4)
	if skull == "":
		skull = my_skull()
	if skull == "":
		skull = _default_pick()
	room["skull"] = skull
	if members.has(1):
		members[1]["skull"] = skull
	_host_game_config = {"mode": mode, "difficulty": int(room["difficulty"]), "skull": skull}
	state = "playing"
	Run.net_role = "host"
	Run.net_slot = 0
	if is_pvp:
		# 对战：主机与客机各自在本机已解锁池里选人，主机只校验角色 id 合法
		if not Meta.is_unlocked(skull):
			state = "lobby"
			Run.net_role = ""
			return "房主化身未解锁，请重新选择"
		var guest_skull := ""
		for id in members:
			if int(members[id].get("slot", 0)) == 1:
				guest_skull = str(members[id].get("skull", ""))
		if guest_skull == "" or not Skulls.ids().has(guest_skull):
			state = "lobby"
			Run.net_role = ""
			return "客机尚未选择化身"
		Run.start_pvp({0: skull, 1: guest_skull}, false)
		Run.set_net_players(2)
	else:
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
	_go(_play_scene(), "正在联机入阵" if is_pvp else "正在联机入卷")
	return ""


## 自己在大厅里选中的化身（主机取房间设置，客机取自己成员条目）。
## 成员条目为空时回落到本机持久化的 my_pick：重连 / 房间重置后不会丢选择。
func my_skull() -> String:
	if role == "client":
		var m: Dictionary = members.get(multiplayer.get_unique_id(), {})
		var picked := str(m.get("skull", ""))
		return picked if picked != "" else my_pick
	return str(room.get("skull", "")) if str(room.get("skull", "")) != "" else my_pick


## 最近一次解锁可用的化身，用作默认选择。
func _default_pick() -> String:
	for id in Skulls.ids():
		if Meta.is_unlocked(str(id)):
			return str(id)
	var all := Skulls.ids()
	return str(all[0]) if not all.is_empty() else ""


## 选中的化身报给主机；开局时按槽位分配，互不覆盖。房主自己也走同一条路径，
## 这样"房主 / 客机"在开局选择上的权限完全对等，且选择会持久化到本机。
func set_my_skull(skull: String) -> void:
	if skull == "" or not Skulls.ids().has(skull):
		return
	my_pick = skull
	if role == "host":
		room["skull"] = skull
		if members.has(1):
			members[1]["skull"] = skull
		_emit_lobby()
	elif role == "client":
		var uid := multiplayer.get_unique_id()
		if members.has(uid):
			members[uid]["skull"] = skull
		if multiplayer.has_multiplayer_peer() and uid != 1 and (state == "lobby" or state == "playing"):
			# 没有真实连接（离线测试）或自己就是服务端时不发 RPC，避免 "RPC on yourself" 报错
			rpc_id(1, "_rpc_skull", skull)


## 客户端就绪状态
func set_ready(ready: bool) -> void:
	if role == "client":
		rpc_id(1, "_rpc_ready", ready)
	elif role == "host" and members.has(1):
		members[1]["ready"] = true
		_emit_lobby()


## 房主把结算数据同步给所有客机；客机据此显示同一份战绩并本地领奖。
func host_settlement(data: Dictionary) -> void:
	if role != "host":
		return
	_emit_event({"kind": "settlement", "data": data.duplicate(true)})


## 客机：房间场景就绪前收到的结算数据先缓冲，避免切场景时丢失。
func take_pending_settlement() -> Dictionary:
	if _pending_settlement.is_empty():
		return {}
	var d := _pending_settlement.duplicate(true)
	_pending_settlement.clear()
	return d


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
	pending_fx.clear()
	snapshot_seq = 0
	_remote_held.clear()
	_remote_just.clear()
	_remote_just_at.clear()
	_remote_axis.clear()
	_pending_just.clear()
	_input_flush = false
	_input_acc = 0.0
	_reserved.clear()
	_choice_kind = ""
	_choice_open = false
	_choice_elapsed = 0.0
	_choice_cards.clear()
	_choice_done.clear()
	_pending_choice.clear()
	_pending_settlement.clear()
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
		"boss_defeated": Run.boss_defeated.duplicate(),
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
		"net_upgrades": Run.slot_upgrades.duplicate(true),
		"net_blessings": Run.slot_blessing.duplicate(),
		"net_blessing_used": Run.slot_blessing_used.duplicate(),
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


## 主机下发一批世界特效。特效是一次性事件，必须走可靠通道，不能被快照丢包吞掉。
func push_fx(events: Array) -> void:
	if role != "host" or state != "playing" or events.is_empty():
		return
	if multiplayer.multiplayer_peer == null:
		return
	_rpc_fx.rpc(events)


## 客机取走所有待回放的世界特效（读即清空）。
func take_pending_fx() -> Array:
	if pending_fx.is_empty():
		return []
	var out := pending_fx
	pending_fx = []
	return out


# ---------------------------------------------------------------- 开局祝福 / 通关强化（三选一）

## 主机发起一次三选一：祝福全队看同一组牌，通关强化按各自槽位的流派等级发牌。
## 房主与客机都会在本机弹面板，选择只落到自己槽位（独立选择、独立生效）。
func host_begin_choice(kind: String) -> void:
	if role != "host" or state != "playing":
		return
	_choice_kind = kind
	_choice_seq += 1
	_choice_open = true
	_choice_elapsed = 0.0
	_choice_done.clear()
	_choice_cards.clear()
	var slots := _choice_slots()
	var shared: Array = []
	if kind == "blessing":
		var pool: Array = Run.BLESSINGS.keys()
		pool.shuffle()
		shared = pool.slice(0, mini(3, pool.size()))
	for s in slots:
		_choice_cards[int(s)] = shared.duplicate() if kind == "blessing" else Run.roll_cards(3, int(s))
	# 房主自己也弹面板
	choice_requested.emit({"kind": kind, "token": _choice_seq,
		"cards": (_choice_cards.get(0, []) as Array).duplicate(), "slot": 0})
	var peers := multiplayer.get_peers()
	for id in members:
		if int(id) == 1 or not peers.has(int(id)):
			continue
		var s := int(members[id].get("slot", -1))
		if s < 0 or not _choice_cards.has(s):
			continue
		_rpc_choice_request.rpc_id(int(id), {"kind": kind, "token": _choice_seq,
			"cards": (_choice_cards[s] as Array).duplicate(), "slot": s})


func _choice_slots() -> Array:
	var out: Array = [0]
	for id in members:
		var s := int(members[id].get("slot", -1))
		if s > 0 and not out.has(s):
			out.append(s)
	out.sort()
	return out


## 本机提交选择：客机只发 key 给主机，房主直接落盘。
## 客机的 _choice_kind 必须在收到请求时写入，否则这里的类型校验会把选择静默丢掉，
## 主机永远等不齐所有人，只能靠 25 秒超时兜底——表现为选完赐福后画面整段卡死。
func submit_choice(kind: String, key: String) -> void:
	if kind != _choice_kind or key == "":
		return
	if role == "host":
		_record_choice(0, key)
	elif role == "client":
		rpc_id(1, "_rpc_choice", key)


## 房主记录某槽位的选择（客机 RPC 与房主本机共用）。
func _record_choice(slot: int, key: String) -> void:
	if not _choice_open or slot < 0:
		return
	var cards: Array = _choice_cards.get(slot, [])
	if not cards.has(key):
		return
	_choice_done[slot] = key
	if _choice_kind == "blessing":
		Run.set_blessing(slot, key)
		if key == "hp":
			# 赐福「生命」的 +2 由 calculated_max_hp 计入；这里把该槽位当前血量补到新上限
			if slot == 0:
				Run.max_hp = Run.calculated_max_hp("", 0)
				Run.hp = Run.max_hp
			else:
				Run.slot_hp[slot] = Run.calculated_max_hp(Run.slot_skull_of(slot), slot)
	elif _choice_kind == "upgrade":
		Run.buy(key, slot)
	if _all_chosen():
		_finish_choice()


func _all_chosen() -> bool:
	for s in _choice_cards.keys():
		if not _choice_done.has(int(s)):
			return false
	return true


## 房主推进前检查：所有人都选完了才能换房；没有进行中的选择时视为可推进。
func choices_complete() -> bool:
	return not _choice_open or _all_chosen()


func _finish_choice() -> void:
	var kind := _choice_kind
	_choice_open = false
	_choice_elapsed = 0.0
	_choice_kind = "" # 关闭后不再接受选择，避免迟到的手指点进下一次三选一
	_emit_event({"kind": "choice_done", "choice": kind, "run": run_payload()})
	choice_resolved.emit(kind)


## 某个槽位迟迟没有提交时用该组第一张补齐；选择关闭后不再写入。
func _autofill_slot(slot: int) -> void:
	if not _choice_open or _choice_done.has(slot):
		return
	var cards: Array = _choice_cards.get(slot, [])
	if not cards.is_empty():
		_record_choice(slot, str(cards[0]))


## 兜底：有人掉线/挂机时，25 秒后用每组第一张自动补齐，避免卡死推进。
func _tick_choice(delta: float) -> void:
	if role != "host" or not _choice_open:
		return
	_choice_elapsed += delta
	if _choice_elapsed < 25.0:
		return
	for s in _choice_cards.keys():
		if not _choice_open:
			break
		_autofill_slot(int(s))
	if _choice_open:
		_finish_choice()


## 客机：房间场景就绪前收到的三选一请求先缓冲，避免切场景时丢请求。
func take_pending_choice(kind := "") -> Dictionary:
	if _pending_choice.is_empty():
		return {}
	if kind != "" and str(_pending_choice.get("kind", "")) != kind:
		return {}
	var d := _pending_choice.duplicate()
	_pending_choice.clear()
	return d


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
		if str(room.get("mode", "")) == Run.MODE_PVP and members.size() >= 2:
			_rpc_join_result.rpc_id(sender, {"ok": false, "reason": "对战房间已满（1v1）"})
			return
		slot = _free_slot()
		if slot < 0:
			_rpc_join_result.rpc_id(sender, {"ok": false, "reason": "房间已满（最多 4 人）"})
			return
	if token == "" or not resumed:
		token = _make_token()
	var name := str(d.get("name", "墨客")).substr(0, 16)
	# 重连时保留客机此前选好的化身，不能用空串覆盖掉
	var prev_skull := str(members.get(sender, {}).get("skull", "")) if resumed else ""
	members[sender] = {"name": name, "slot": slot, "ready": false, "token": token, "skull": prev_skull}
	# 开局后中途加入/重连：人数立即影响后续波次的难度行
	if state == "playing":
		Run.set_net_players(members.size())
	_rpc_join_result.rpc_id(sender, {
		"ok": true, "slot": slot, "token": token, "resumed": resumed,
		"state": state, "room": room.duplicate(true), "game": _host_game_config.duplicate(true),
		"run": run_payload() if state == "playing" else {},
	})
	# 重连落在三选一进行中：把当前请求补发给该客机，否则它的席位会一直等超时
	if state == "playing" and _choice_open and _choice_cards.has(slot) and not _choice_done.has(slot):
		var cards: Array = _choice_cards.get(slot, [])
		_rpc_choice_request.rpc_id(sender, {"kind": _choice_kind, "token": _choice_seq,
			"cards": cards.duplicate(), "slot": slot})
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
	# 房间清理 / 重连后恢复自己的化身选择，并立即上报主机，避免"客机尚未选择化身"卡住开局
	if state == "lobby":
		if my_pick == "":
			my_pick = _default_pick()
		if my_pick != "":
			set_my_skull(my_pick)
	_host_game_config = d.get("game", {}) if d.get("game", {}) is Dictionary else {}
	_last_pong_ms = Time.get_ticks_msec()
	_reconnecting = false
	_reconnect_left = 0
	# 断线期间的三选一请求可能已经结束：旧缓冲必须作废，否则重连进场会再弹一次
	# 永远等不到 choice_done 的面板，把本机永久暂停。若主机仍在选择中，随后会补发新请求。
	_pending_choice.clear()
	_choice_kind = ""
	joined.emit(resumed)
	if resumed:
		link_restored.emit()
	if state == "playing":
		if Run.meta_snapshot.is_empty():
			Run.meta_snapshot = Meta.snapshot()
		_apply_run_sync(d.get("run", {}) if d.get("run", {}) is Dictionary else {})
		session_started.emit(_host_game_config)
		if auto_enter_room:
			_go(_play_scene(), "正在联机入卷")


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
			# 三选一进行中离开：立即补齐该席位，别让剩下的人一直停在暂停画面
			_autofill_slot(left_slot)
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
	# 以开局配置为准覆盖房间模式，确保客户端也进到正确场景（对战 / PvE）
	if _host_game_config.has("mode"):
		room["mode"] = str(_host_game_config["mode"])
	state = "playing"
	# 客机也要有自己的局内 Meta 基线，结算面板才能展示本局契合/解锁收获
	Run.meta_snapshot = Meta.snapshot()
	_apply_run_sync(data.get("run", {}) if data.get("run", {}) is Dictionary else {})
	session_started.emit(_host_game_config)
	if auto_enter_room:
		_go(_play_scene(), "正在联机入卷")


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
			_go(_play_scene(), "正在入卷")
		"choice_done":
			# 主机确认所有人的选择已落盘：客机应用同步后的 Run 并关闭等待态
			_pending_choice.clear()
			_choice_kind = "" # 本次三选一结束，迟到的点击不再上送
			var run: Dictionary = ev.get("run", {}) if ev.get("run", {}) is Dictionary else {}
			if not run.is_empty():
				_apply_run_sync(run)
			choice_resolved.emit(str(ev.get("choice", "")))
		"settlement":
			# 主机结算：先缓冲，房间场景就绪后再弹面板；已就绪则立即通知
			var data: Dictionary = ev.get("data", {}) if ev.get("data", {}) is Dictionary else {}
			_pending_settlement = data.duplicate(true)
			settlement.emit(data)
		"session_end":
			var reason := str(ev.get("reason", "对局已结束"))
			teardown(reason, true)
			# 客机正在看结算时不要强制回主菜单，等玩家看完自己点「回主菜单」
			var scene := get_tree().current_scene
			if scene != null and scene.find_child("Settlement", true, false) != null:
				return
			_go(MENU_SCENE, "正在收卷")
		"notice":
			net_notice.emit(str(ev.get("text", "")))


# ---------------------------------------------------------------- RPC：三选一（祝福 / 通关强化）

@rpc("authority", "call_remote", "reliable", Cfg.CH_CONTROL)
func _rpc_choice_request(d: Dictionary) -> void:
	if role != "client":
		return
	# 客机必须记住本次三选一的类型与序号：submit_choice 用 _choice_kind 校验类型，
	# 漏写会让客机的每一次选择都被丢弃，主机只能等到 25 秒超时后才自动补齐。
	_choice_kind = str(d.get("kind", ""))
	_choice_seq = int(d.get("token", _choice_seq))
	# 房间场景可能还没 _ready：先缓冲，房间就绪后用 take_pending_choice() 取
	_pending_choice = d.duplicate(true)
	choice_requested.emit(d)


@rpc("any_peer", "call_remote", "reliable", Cfg.CH_CONTROL)
func _rpc_choice(key: String) -> void:
	if role != "host":
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0 or not members.has(sender):
		return
	_record_choice(int(members[sender].get("slot", -1)), key)


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


@rpc("authority", "call_remote", "reliable", Cfg.CH_CONTROL)
func _rpc_fx(events: Array) -> void:
	if role != "client":
		return
	fx_received += events.size()
	pending_fx.append_array(events)
	if pending_fx.size() > 128:
		pending_fx = pending_fx.slice(pending_fx.size() - 128)


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
		# 三选一进行中掉线：不能把全队锁在暂停里等一个已经不在的席位，先按第一张补齐
		_autofill_slot(gone_slot)
		net_notice.emit("队友已断开，保留席位 %d 秒等待重连" % int(Cfg.RECONNECT_GRACE))
	else:
		_emit_lobby()


# ---------------------------------------------------------------- 内部节拍

func _sample_input_edges() -> void:
	# 客机永远采样「本机设备」的输入：PC 用设置里的 P1 键位，移动端由 TouchControls
	# 注入同名基础动作。绝不能走 LocalCoop 的 P2 通道——那会让 PC 客机只能用方向键，
	# 而移动端根本没有 P2 触屏映射，表现为完全无法操作。
	for a in Cfg.ACTIONS:
		if Input.is_action_just_pressed(str(a)):
			_pending_just[str(a)] = true
			_input_flush = true


func _pump_input(delta: float, force := false) -> void:
	_input_acc += delta
	if not force and _input_acc < 1.0 / Cfg.INPUT_HZ:
		return
	_input_acc = 0.0
	if multiplayer.multiplayer_peer == null:
		return
	var held: Array = []
	for a in Cfg.ACTIONS:
		if Input.is_action_pressed(str(a)):
			held.append(a)
	var axis := 0
	if Input.is_action_pressed("move_left"):
		axis -= 1
	if Input.is_action_pressed("move_right"):
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
	var sup = d.get("net_upgrades", {})
	Run.slot_upgrades = (sup as Dictionary).duplicate(true) if sup is Dictionary else {}
	var sbl = d.get("net_blessings", {})
	Run.slot_blessing = (sbl as Dictionary).duplicate() if sbl is Dictionary else {}
	var sbu = d.get("net_blessing_used", {})
	Run.slot_blessing_used = (sbu as Dictionary).duplicate() if sbu is Dictionary else {}
	Run.blessing = str(d.get("blessing", ""))
	Run.boss_id = str(d.get("boss", ""))
	var queue = d.get("boss_queue", [])
	Run.boss_queue = (queue as Array).duplicate() if queue is Array else []
	var defeated = d.get("boss_defeated", [])
	Run.boss_defeated = (defeated as Array).duplicate() if defeated is Array else []
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
	if Run.mode == Run.MODE_PVP:
		# 对战的双方化身随 Run 一起下发；客户端据此生成本地镜像角色
		Run.pvp_skulls = Run.slot_skull.duplicate(true)
		Run.pvp_local = false


## 当前房间应进入的场景：PvE 回房间，对战进竞技场
func _play_scene() -> String:
	return PVP_SCENE if str(room.get("mode", "")) == Run.MODE_PVP else ROOM_SCENE


func _go(path: String, veil_text: String) -> void:
	if not auto_enter_room or _transitioning:
		return
	_transitioning = true
	await LoadVeil.transition_to(path, veil_text)
	_transitioning = false
