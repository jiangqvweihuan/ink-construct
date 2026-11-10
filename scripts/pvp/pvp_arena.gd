extends Node2D

## 玩家对战竞技场：本机同屏 1v1 与双端局域网 1v1 共用。
## 主机/离线跑 pvp_rules 权威结算；客户端只做镜像，靠 NetSync 快照与本场景的状态 RPC 同步。

const PVP_RULES := preload("res://scripts/pvp/pvp_rules.gd")
const NET_SYNC := preload("res://scripts/net/net_sync.gd")
const Skulls := preload("res://scripts/player/skulls.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_BACK := preload("res://audio/sfx/ui_back.wav")

const ROOM_W := 1920.0
const GROUND_Y := 640.0
const SPAWNS := {
	0: Vector2(620.0, 560.0),
	1: Vector2(1300.0, 560.0),
}

const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.82, 0.79, 0.72)
const RED := Color(0.72, 0.24, 0.18)
const BLUE := Color(0.22, 0.44, 0.52)
const GOLD := Color(0.9, 0.75, 0.3)

const BAR_W := 280.0
const BAR_H := 16.0
const HUD_LEFT := 40.0

var _players: Array = [] # slot -> player（NetSync 依赖此字段）
var _rules = null
var _camera: Camera2D
var _local_cam := false
var _hud: CanvasLayer
var _hp_fills: Dictionary = {}
var _score_labels: Dictionary = {}
var _round_label: Label
var _banner: Label
var _banner_tween: Tween
var _result_panel: Control
var _sfx: AudioStreamPlayer

var _is_host := false
var _is_client := false
var _leaving := false
var _broadcast_acc := 0.0
var _hud_acc := 0.0
var _round_token := 0

# 客户端本地缓存的权威状态
var _net_hp: Dictionary = {}
var _net_scores: Dictionary = {}
var _net_round := 1
var _net_phase := "idle"
var _net_winner := -1

var _opponent_missing := 0.0


func _ready() -> void:
	set_meta("battle_width", ROOM_W)
	Run.active = true
	_is_host = Run.net_role == "host"
	_is_client = Run.net_role == "client"
	BGM.play_bgm("battle")
	BGM.stop_voice()
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	_sfx.stream = SFX_CLICK
	add_child(_sfx)

	_build_background()
	_build_ground()
	_spawn_players()
	_build_hud()

	if _is_client:
		_setup_client()
	elif _is_host:
		_setup_rules()
		_attach_net_sync()
		_start_first_round()
	else:
		_setup_rules()
		_start_first_round()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_leave()


func _process(delta: float) -> void:
	_hud_acc += delta
	if _hud_acc >= 0.1:
		_hud_acc = 0.0
		_refresh_hud()
	if _local_cam:
		_tick_local_camera()
	if _is_host and _rules != null:
		_broadcast_acc += delta
		if _broadcast_acc >= 0.25:
			_broadcast_acc = 0.0
			_broadcast_state()
	if (Run.net_role != "" or _is_host) and not _leaving:
		_check_opponent_left(delta)


func _check_opponent_left(delta: float) -> void:
	if LanNet.state != "playing" or LanNet.members.size() >= 2:
		_opponent_missing = 0.0
		return
	# 成员表还没同步过来（0 人）时先不判，避免刚进场景就误判掉线
	if LanNet.members.is_empty():
		return
	_opponent_missing += delta
	if _opponent_missing < 1.0:
		return
	_opponent_missing = 0.0
	_flash_banner("对手已离开")
	await get_tree().create_timer(0.8).timeout
	if is_inside_tree() and not _leaving:
		_leave()


# ---------------------------------------------------------------- 场景搭建

func _load_tex(path: String) -> Texture2D:
	return ResourceLoader.load(path, "Texture2D") as Texture2D


func _build_background() -> void:
	var bg := Sprite2D.new()
	bg.texture = _load_tex("res://art/environment/background/bg_main.png")
	bg.centered = false
	bg.position = Vector2.ZERO
	add_child(bg)

	var tree_l := Sprite2D.new()
	tree_l.texture = _load_tex("res://art/environment/foreground/fg_tree_l.png")
	tree_l.centered = false
	tree_l.position = Vector2(-30, -90)
	tree_l.scale = Vector2(0.72, 0.72)
	tree_l.modulate.a = 0.85
	tree_l.z_index = 10
	add_child(tree_l)

	var tree_r := Sprite2D.new()
	tree_r.texture = _load_tex("res://art/environment/foreground/fg_tree_r.png")
	tree_r.centered = false
	tree_r.position = Vector2(ROOM_W - 431.0 * 0.72 + 30.0, -80.0)
	tree_r.scale = Vector2(0.72, 0.72)
	tree_r.modulate.a = 0.85
	tree_r.z_index = 10
	add_child(tree_r)


func _build_ground() -> void:
	var g := TextureRect.new()
	g.texture = _load_tex("res://art/environment/tilesets/ground_ink.png")
	g.size = Vector2(ROOM_W, 110)
	g.position = Vector2(0, GROUND_Y - 20)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(g)

	var body := StaticBody2D.new()
	body.position = Vector2(ROOM_W * 0.5, GROUND_Y + 40)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(ROOM_W, 80)
	shape.shape = rect
	body.add_child(shape)
	add_child(body)

	for x in [-20.0, ROOM_W + 20.0]:
		var wall := StaticBody2D.new()
		wall.position = Vector2(x, 360)
		var ws := CollisionShape2D.new()
		var wr := RectangleShape2D.new()
		wr.size = Vector2(40, 720)
		ws.shape = wr
		wall.add_child(ws)
		add_child(wall)


## 只取前两个槽位：本机同屏与双端局域网都是 1v1
func _picks() -> Dictionary:
	var picks: Dictionary = Run.pvp_skulls.duplicate(true)
	if picks.is_empty():
		picks = Run.slot_skull.duplicate(true)
	if not picks.has(0):
		picks[0] = Skulls.DEFAULT_ID
	if not picks.has(1):
		picks[1] = str(picks[0])
	return {0: str(picks[0]), 1: str(picks[1])}


func _spawn_players() -> void:
	var picks := _picks()
	for slot in 2:
		var id := str(picks.get(slot, Skulls.DEFAULT_ID))
		var p = load(PLAYER_SCENE).instantiate()
		if not p.has_signal("died"):
			push_error("pvp_arena: 玩家脚本未加载（检查 player.gd 编译错误）")
			return
		p.input_slot = slot
		p.position = SPAWNS[slot]
		p.facing = 1 if slot == 0 else -1
		add_child(p)
		if str(p.skull_id) != id:
			p.swap_skull(id)
		p.pvp_mode = true
		p.add_to_group("pvp_players") # player._foes() 据此把对手玩家当作技能目标
		p.max_hp = PVP_RULES.MAX_HP
		p.hp = PVP_RULES.MAX_HP
		p.hp_changed.emit(p.hp, p.max_hp)
		_players.append(p)

	# swap_skull 会把 Run 的化身写成最后一次换头；全部生成完后恢复成 P1
	Run.skull_id = str(picks[0])
	Run.slot_skull = picks.duplicate()
	for slot in _players.size():
		Run.slot_hp[slot] = PVP_RULES.MAX_HP

	var follow = _players[0]
	var want_slot := Run.net_slot if Run.net_role != "" else 0
	if want_slot >= 0 and want_slot < _players.size():
		follow = _players[want_slot]
	if Run.net_role == "":
		# 本机同屏：镜头追两人中点并随距离缩放，保证双方始终同框
		_setup_local_camera()
	else:
		_setup_camera(follow)


func _setup_local_camera() -> void:
	_local_cam = true
	_camera = Camera2D.new()
	_camera.position = Vector2(ROOM_W * 0.5, GROUND_Y - 120.0)
	_camera.limit_left = 0
	_camera.limit_right = int(ROOM_W)
	_camera.limit_top = 0
	_camera.limit_bottom = 720
	add_child(_camera)
	_camera.make_current()
	Feel.register_camera(_camera)


func _tick_local_camera() -> void:
	if _camera == null or _players.size() < 2:
		return
	if not is_instance_valid(_players[0]) or not is_instance_valid(_players[1]):
		return
	var mid: Vector2 = (_players[0].global_position + _players[1].global_position) * 0.5
	_camera.global_position = _camera.global_position.lerp(mid + Vector2(0, -110), 0.12)
	var dist := absf(_players[0].global_position.x - _players[1].global_position.x)
	var want := clampf(1280.0 / maxf(dist + 520.0, 1.0), 0.62, 1.0)
	_camera.zoom = _camera.zoom.lerp(Vector2(want, want), 0.08)


func _setup_camera(follow) -> void:
	_camera = Camera2D.new()
	_camera.position = Vector2(0, -80)
	_camera.limit_left = 0
	_camera.limit_right = int(ROOM_W)
	_camera.limit_top = 0
	_camera.limit_bottom = 720
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	follow.add_child(_camera)
	_camera.make_current()
	Feel.register_camera(_camera)


func _attach_net_sync() -> void:
	var ns = NET_SYNC.new()
	ns.name = "NetSync"
	ns.room = self
	add_child(ns)


func _setup_rules() -> void:
	_rules = PVP_RULES.new()
	_rules.name = "PvpRules"
	add_child(_rules)
	for slot in _players.size():
		var p = _players[slot]
		_rules.register(slot, p)
		p.pvp_strike.connect(_on_pvp_strike.bind(slot))
	_rules.hp_changed.connect(_on_hp_changed)
	_rules.round_started.connect(_on_round_started)
	_rules.round_ended.connect(_on_round_ended)
	_rules.match_ended.connect(_on_match_ended)


func _setup_client() -> void:
	for p in _players:
		if is_instance_valid(p):
			p.net_puppet = true
	_attach_net_sync()
	_flash_banner("等待主机开战…", 99.0)


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 20
	add_child(_hud)
	UiKit.fit_layer(_hud)

	var picks := _picks()
	for slot in 2:
		var left: bool = slot == 0
		var base_x := HUD_LEFT if left else 1280.0 - HUD_LEFT - BAR_W
		var color := RED if left else BLUE
		var name_label := UiKit.label(
			_hud, "%s  P%d" % [_profile_label(str(picks[slot])), slot + 1],
			Vector2(base_x, 22), Vector2(BAR_W, 30), 22, PAPER,
			HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
		)
		name_label.name = "PvpName%d" % slot
		UiKit.rule(_hud, Vector2(base_x, 56), Vector2(BAR_W, 3), Color(PAPER.r, PAPER.g, PAPER.b, 0.35))
		var bg := ColorRect.new()
		bg.color = Color(0.1, 0.08, 0.06, 0.72)
		bg.position = Vector2(base_x, 64)
		bg.size = Vector2(BAR_W, BAR_H)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.add_child(bg)
		var fill := ColorRect.new()
		fill.color = color
		fill.position = Vector2(base_x, 64)
		fill.size = Vector2(BAR_W, BAR_H)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.add_child(fill)
		_hp_fills[slot] = fill

		var score := UiKit.label(
			_hud, "", Vector2(base_x, 88), Vector2(BAR_W, 28), 22, GOLD,
			HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
		)
		_score_labels[slot] = score

	_round_label = UiKit.label(_hud, "第 1 回合", Vector2(540, 22), Vector2(200, 30), 22, PAPER)
	_banner = UiKit.label(_hud, "", Vector2(240, 238), Vector2(800, 90), 44, PAPER)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	_banner.add_theme_constant_override("outline_size", 8)

	UiKit.texture_button(
		_hud, "退  出", Vector2(580, 664), Vector2(120, 40), 18, DIM, _leave
	)
	_refresh_hud()


func _profile_label(id: String) -> String:
	return str(Skulls.get_profile(id).get("label", id))


func _player_name(slot: int) -> String:
	if slot >= 0 and slot < _players.size() and is_instance_valid(_players[slot]):
		return _profile_label(str(_players[slot].skull_id))
	return "P%d" % (slot + 1)


func _hp_of(slot: int) -> int:
	if slot >= 0 and slot < _players.size() and is_instance_valid(_players[slot]):
		return int(_players[slot].hp)
	return int(_net_hp.get(slot, 0))


func _scores_now() -> Dictionary:
	return _rules.scores if _rules != null else _net_scores


func _round_now() -> int:
	return int(_rules.round_no) if _rules != null else _net_round


func _phase_now() -> String:
	return str(_rules.phase) if _rules != null else _net_phase


func _winner_now() -> int:
	return int(_rules.winner) if _rules != null else _net_winner


func _refresh_hud() -> void:
	for slot in 2:
		var fill = _hp_fills.get(slot)
		if fill is ColorRect:
			var ratio := clampf(float(_hp_of(slot)) / float(PVP_RULES.MAX_HP), 0.0, 1.0)
			fill.size = Vector2(BAR_W * ratio, BAR_H)
		var score_label = _score_labels.get(slot)
		if score_label is Label:
			var got := int(_scores_now().get(slot, 0))
			var text := ""
			for i in PVP_RULES.ROUNDS_TO_WIN:
				text += "● " if i < got else "○ "
			score_label.text = text.strip_edges()
	if _round_label != null:
		_round_label.text = "第 %d 回合" % maxi(1, _round_now())


func _flash_banner(text: String, hold := 1.2) -> void:
	if _banner == null:
		return
	_banner.text = text
	_banner.modulate.a = 1.0
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	if hold >= 90.0:
		return
	_banner_tween = create_tween()
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.4)


# ---------------------------------------------------------------- 回合流程（主机/离线）

func _start_first_round() -> void:
	_round_token += 1
	_rules.begin_round()
	_apply_round_start(_round_token)


func _start_next_round() -> void:
	_round_token += 1
	_rules.next_round()
	_apply_round_start(_round_token)


func _apply_round_start(token: int) -> void:
	_freeze(true)
	_close_result()
	_flash_banner("第 %d 回合" % _rules.round_no, 1.0)
	for slot in _players.size():
		var p = _players[slot]
		if not is_instance_valid(p):
			continue
		p.pvp_reset(SPAWNS.get(slot, Vector2(960, 560)))
		p.facing = 1 if slot == 0 else -1
		p.call("_apply_facing")
		p.pvp_frozen = true
	_refresh_hud()
	_broadcast_state()
	await get_tree().create_timer(1.0).timeout
	if token != _round_token or not is_inside_tree():
		return
	_freeze(false)
	_flash_banner("对  决", 0.6)


func _freeze(on: bool) -> void:
	for p in _players:
		if is_instance_valid(p):
			p.pvp_frozen = on


func _on_pvp_strike(spec: Dictionary, attacker_slot: int) -> void:
	if _rules == null:
		return
	_rules.handle_strike(int(attacker_slot), spec)


func _on_hp_changed(_slot: int, _hp: int, _max_hp: int) -> void:
	_refresh_hud()
	_broadcast_state()


func _on_round_started(round_no: int) -> void:
	_flash_banner("第 %d 回合" % round_no, 1.0)
	_refresh_hud()


func _on_round_ended(winner_slot: int, _scores: Dictionary) -> void:
	_freeze(true)
	_flash_banner("%s 得手" % _player_name(winner_slot), 1.3)
	_broadcast_state()
	if _rules.phase == "match_end":
		return
	var token := _round_token
	await get_tree().create_timer(1.4).timeout
	if token != _round_token or not is_inside_tree() or _leaving:
		return
	if _rules.phase == "round_end":
		_start_next_round()


func _on_match_ended(winner_slot: int, _scores: Dictionary) -> void:
	_freeze(true)
	_broadcast_state()
	_show_result(winner_slot)


# ---------------------------------------------------------------- 局域网状态同步

@rpc("authority", "call_remote", "reliable")
func _rpc_pvp_state(d: Dictionary) -> void:
	if not _is_client:
		return
	_net_hp = (d.get("hp", {}) as Dictionary).duplicate()
	_net_phase = str(d.get("phase", "fight"))
	_net_winner = int(d.get("winner", -1))
	var new_round := int(d.get("round", 1))
	if new_round != _net_round:
		_net_round = new_round
		_flash_banner("第 %d 回合" % new_round, 1.0)
	var scores: Dictionary = d.get("scores", {})
	for slot in scores:
		if int(scores[slot]) > int(_net_scores.get(int(slot), 0)):
			_flash_banner("%s 得手" % _player_name(int(slot)), 1.3)
	_net_scores = scores.duplicate()
	if _net_phase == "match_end":
		_freeze(true)
		_show_result(_net_winner)
	else:
		_close_result()
	_refresh_hud()


func _broadcast_state() -> void:
	if not _is_host or _rules == null or multiplayer.multiplayer_peer == null:
		return
	_rpc_pvp_state.rpc(_rules.snapshot())


# ---------------------------------------------------------------- 结算层

func _show_result(winner_slot: int) -> void:
	if is_instance_valid(_result_panel):
		return
	_result_panel = ColorRect.new()
	_result_panel.color = Color(0, 0, 0, 0.66)
	_result_panel.size = Vector2(1280, 720)
	_result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud.add_child(_result_panel)

	var win_color := RED if winner_slot == 0 else BLUE
	UiKit.label(_result_panel, "对 决 终 了", Vector2(0, 190), Vector2(1280, 60), 34, PAPER)
	UiKit.label(
		_result_panel, "%s 胜" % _player_name(winner_slot),
		Vector2(0, 250), Vector2(1280, 80), 54, win_color
	)
	var score := _scores_now()
	UiKit.label(
		_result_panel,
		"P1  %d  :  %d  P2" % [int(score.get(0, 0)), int(score.get(1, 0))],
		Vector2(0, 330), Vector2(1280, 40), 24, GOLD
	)

	var btn_y := 430.0
	if not _is_client:
		UiKit.texture_button(
			_result_panel, "再  战", Vector2(370, btn_y), Vector2(200, 56), 24, PAPER,
			_restart_match
		)
		UiKit.texture_button(
			_result_panel, "退  出", Vector2(710, btn_y), Vector2(200, 56), 24, PAPER,
			_leave
		)
	else:
		UiKit.texture_button(
			_result_panel, "退出对战", Vector2(540, btn_y), Vector2(200, 56), 24, PAPER,
			_leave
		)


func _close_result() -> void:
	if is_instance_valid(_result_panel):
		_result_panel.queue_free()
	_result_panel = null


func _restart_match() -> void:
	if _rules == null:
		return
	_round_token += 1
	_rules.reset_match()
	_apply_round_start(_round_token)
	if _is_host:
		_broadcast_state()


# ---------------------------------------------------------------- 退出

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	_round_token += 1
	_freeze(true)
	_play_sfx(SFX_BACK)
	Run.active = false
	if _is_host:
		await LanNet.host_end_session("对战结束")
		await LoadVeil.transition_to("res://scenes/ui/main_menu.tscn", "正在收卷")
	elif _is_client:
		await LanNet.leave()
		await LoadVeil.transition_to("res://scenes/ui/main_menu.tscn", "正在收卷")
	else:
		await LoadVeil.transition_to("res://scenes/ui/main_menu.tscn", "正在收卷")


func _play_sfx(stream: AudioStream) -> void:
	if _sfx == null or not is_instance_valid(_sfx):
		return
	_sfx.stream = stream
	_sfx.play()
