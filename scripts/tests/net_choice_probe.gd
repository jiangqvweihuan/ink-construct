extends Node

## 联机三选一集成回归（2~4 进程真实 ENet）：
## 主机开局后依次发起「开局赐福」与「通关强化」，每个进程按真实面板的行为暂停本机、
## 收到请求后提交选择，并在 choice_resolved 后恢复。
## 复现并锁死：客机提交被静默丢弃 -> 主机等 25 秒超时 -> 选完赐福后整段卡死。
##
## 主机：godot --headless --path . res://scenes/tests/net_choice_probe.tscn -- --role=host --players=2
## 客机：godot --headless --path . res://scenes/tests/net_choice_probe.tscn -- --role=client --players=2
## 四进程：--players=4，另起 3 个客机。必须在 20 秒内完成两轮三选一，
## 一旦退化成 25 秒超时兜底，探针直接判失败。

const Cfg = preload("res://scripts/net/net_config.gd")

var role := ""
var want_players := 2
var fail := 0
var finished := false
var t := 0.0

var started := false
var phase := ""
var phase_at := 0.0
var expected_slots: Array = []
var picked_key := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	role = _arg("--role=", "host")
	want_players = clampi(int(_arg("--players=", "2")), 2, Cfg.MAX_PLAYERS)
	LanNet.auto_enter_room = false
	LanNet.choice_requested.connect(_on_choice_requested)
	LanNet.choice_resolved.connect(_on_choice_resolved)
	if role == "host":
		expected_slots = range(want_players)
		LanNet.lobby_changed.connect(_on_lobby)
		var err := LanNet.host_room("三选一回归房", Run.MODE_ADVENTURE, 1, "c021")
		_check("host_create_room", err == "", err)
	else:
		var err := LanNet.join_room("127.0.0.1")
		_check("client_join_call", err == "", err)


func _process(delta: float) -> void:
	t += delta
	if not finished and t > 20.0:
		_check("no_timeout", false, "phase=%s state=%s paused=%s" % [phase, LanNet.state, str(get_tree().paused)])
		_done()


# ---------------------------------------------------------------- 主机

func _on_lobby(_data: Dictionary) -> void:
	if role != "host" or started:
		return
	if LanNet.state != "lobby" or LanNet.members.size() < want_players:
		return
	started = true
	var err := LanNet.start_game(Run.MODE_ADVENTURE, 1, "c021")
	_check("host_start_game", err == "", err)
	await get_tree().create_timer(0.5, true).timeout
	_begin_phase("blessing")


func _begin_phase(kind: String) -> void:
	if finished:
		return
	phase = kind
	phase_at = t
	get_tree().paused = true # 模拟三选一面板：真实面板 _ready 同样暂停整棵树
	LanNet.host_begin_choice(kind)
	await get_tree().process_frame
	_check("phase_open_" + kind, LanNet._choice_open, "open=%s" % str(LanNet._choice_open))


# ---------------------------------------------------------------- 两端共用

func _on_choice_requested(d: Dictionary) -> void:
	var kind := str(d.get("kind", ""))
	var cards: Array = d.get("cards", [])
	_check("request_" + kind + "_" + role, not cards.is_empty(), str(cards.size()))
	if role == "client":
		# 客机回归重点：请求到达时必须成功写下 _choice_kind，否则 submit_choice 会丢弃选择
		_check("client_armed_" + kind, LanNet._choice_kind == kind, LanNet._choice_kind)
	phase = kind
	phase_at = t
	picked_key = str(cards[0]) if not cards.is_empty() else ""
	get_tree().paused = true
	await get_tree().create_timer(0.15, true).timeout
	if finished or picked_key == "":
		return
	LanNet.submit_choice(kind, picked_key)


func _on_choice_resolved(kind: String) -> void:
	get_tree().paused = false
	if finished:
		return
	var elapsed := t - phase_at
	if role == "host":
		_check("host_resolved_" + kind, kind == phase, "%s/%s" % [kind, phase])
		_check("host_fast_" + kind, elapsed < 5.0, "%.2fs" % elapsed)
		for s in expected_slots:
			_check("host_slot_%d_%s" % [s, kind], LanNet._choice_done.has(int(s)), str(LanNet._choice_done))
		await get_tree().create_timer(0.3, true).timeout
		if kind == "blessing":
			_begin_phase("upgrade")
		else:
			_done()
	else:
		_check("client_resolved_" + kind, kind == phase, "%s/%s" % [kind, phase])
		_check("client_disarmed_" + kind, LanNet._choice_kind == "", LanNet._choice_kind)
		var slot := int(Run.net_slot)
		if kind == "blessing":
			_check("client_applied_blessing", Run.blessing_of(slot) != "", Run.blessing_of(slot))
		else:
			_check("client_applied_upgrade", Run.level(picked_key, slot) >= 1, picked_key)
		if kind == "upgrade":
			await get_tree().create_timer(0.3, true).timeout
			_done()


# ---------------------------------------------------------------- 工具

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
	print("PROBE RESULT role=%s players=%d fail=%d" % [role, want_players, fail])
	await get_tree().create_timer(0.3, true).timeout
	get_tree().quit(1 if fail > 0 else 0)
