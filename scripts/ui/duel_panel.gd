extends CanvasLayer

## 斗蛐蛐面板：红蓝两队各挑 1~3 名敌人（杂兵 / 首领），用 −/＋ 调沙盒数值，
## 开始后全自动对打。三种形态：config（选人与调数值）/ battle（观战）/ result（胜负）。

signal start_requested(red_ids, blue_ids, red_stats, blue_stats)
signal rematch_requested
signal config_requested
signal back_requested

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Roster = preload("res://scripts/modes/duel_roster.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_DECIDE := preload("res://audio/sfx/shop_purchase.wav")

const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.80, 0.77, 0.70)
const UNKNOWN_COLOR := Color(0.52, 0.50, 0.47)
const RED_COLOR := Color(0.87, 0.38, 0.31)
const BLUE_COLOR := Color(0.44, 0.64, 0.94)
const MAX_TEAM := 4

const STAT_ROWS := [
	{"key": "hp", "label": "生命", "min": 10.0, "max": 150.0, "step": 10.0},
	{"key": "atk", "label": "攻击", "min": 0.5, "max": 3.0, "step": 0.1},
	{"key": "spd", "label": "移速", "min": 100.0, "max": 360.0, "step": 20.0},
	{"key": "gap", "label": "出手", "min": 0.4, "max": 2.0, "step": 0.1},
]

# ---------- 选人页几何（1280×720）：左右两张卡，卡内 4×5 名录格 + 2×2 数值格 ----------
const CARD_W := 560.0
const CARD_H := 516.0
const CARD_Y := 80.0
const CARD_X := [40.0, 680.0] # 红 / 蓝
const CHIP_W := 124.0
const CHIP_H := 44.0
const CHIP_GAP := 8.0
const CHIP_COLS := 4
const GRID_TOP := 104.0
const STAT_TOP := 370.0
const STAT_W := 252.0
const STAT_H := 58.0

# ---------- 观战血条：红队从左往右，蓝队从右往左，每队最多三行 ----------
const HUD_TOP := 14.0
const HUD_ROW_H := 36.0
const HUD_LBL_W := 190.0
const HUD_BAR_W := 300.0
const HUD_BAR_X := 240.0

var _mode := "config"
var _roster: Array = []
var _red_ids: Array = ["c016"]
var _blue_ids: Array = ["c035"]
var _team_size := 1
var _red_stats := {"hp": 20.0, "atk": 1.0, "spd": 200.0, "gap": 1.0}
var _blue_stats := {"hp": 20.0, "atk": 1.0, "spd": 200.0, "gap": 1.0}
var _result_text := ""
var _result_color := PAPER
var _sfx: AudioStreamPlayer
var _bound_red: Array = []
var _bound_blue: Array = []
var _rows_red: Array = []
var _rows_blue: Array = []


func _ready() -> void:
	layer = 8
	_roster = Roster.entries()
	_red_ids = _sanitize(_red_ids)
	_blue_ids = _sanitize(_blue_ids)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()


func _process(_delta: float) -> void:
	if _mode != "battle":
		return
	for i in MAX_TEAM:
		_tick_slot(_rows_red, _bound_red, i, true)
		_tick_slot(_rows_blue, _bound_blue, i, false)


func _tick_slot(rows: Array, team: Array, i: int, is_red: bool) -> void:
	if i >= rows.size():
		return
	var row: Control = rows[i]
	if i >= team.size() or not is_instance_valid(team[i]):
		row.visible = false
		return
	row.visible = true
	var f = team[i]
	var hp := float(f.get("hp"))
	var mx := maxf(float(f.get("max_hp")), 1.0)
	var ratio := clampf(hp / mx, 0.0, 1.0)
	var fill: ColorRect = row.get_meta("fill")
	var lbl: Label = row.get_meta("lbl")
	fill.size.x = HUD_BAR_W * ratio
	fill.position.x = (HUD_BAR_X if is_red else HUD_BAR_X + HUD_BAR_W * (1.0 - ratio) + 500.0)
	lbl.text = "%s %d / %d" % [str(f.get_meta("duel_name", "?")), int(ceil(hp)), int(mx)]
	lbl.modulate = Color(1, 1, 1, 1) if hp > 0.0 else Color(1, 1, 1, 0.45)


func bind_fighters(red_team: Array, blue_team: Array) -> void:
	_bound_red = red_team
	_bound_blue = blue_team


func show_result(text: String, color: Color) -> void:
	_result_text = text
	_result_color = color
	_mode = "result"
	_refresh()


func _refresh() -> void:
	for c in get_children():
		if c == _sfx:
			continue
		remove_child(c)
		c.queue_free()
	_rows_red = []
	_rows_blue = []
	var vw: float = get_viewport().get_visible_rect().size.x
	var root := Control.new()
	root.position = Vector2(maxf(0.0, (vw - 1280.0) * 0.5), 0)
	root.size = Vector2(1280, 720)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	match _mode:
		"battle":
			_build_battle(root)
		"result":
			_build_result(root)
		_:
			_build_config(root)


# ============================ 选人 / 调数值 ============================

func _build_config(root: Control) -> void:
	UiKit.label(root, "斗 蛐 蛐", Vector2(0, 2), Vector2(1280, 50), 40, PAPER, HORIZONTAL_ALIGNMENT_CENTER, false)
	UiKit.label(root, "全部杂兵与首领同场 · 点名录可多选 · 拉数值 · 全自动观战",
		Vector2(0, 50), Vector2(1280, 20), 13, DIM, HORIZONTAL_ALIGNMENT_CENTER, false)
	_btn(root, "返  回", Vector2(36, 18), Vector2(120, 44), 18, func(): back_requested.emit())
	_build_size_stepper(root)
	_build_card(root, CARD_X[0], true)
	_build_card(root, CARD_X[1], false)
	var start_btn := _btn(root, "开 始 对 决", Vector2(480, 616), Vector2(320, 64), 26, _start_battle)
	if _red_ids.is_empty() or _blue_ids.is_empty():
		start_btn.disabled = true
		start_btn.modulate = Color(1, 1, 1, 0.35)
		UiKit.label(root, "图鉴尚未收录任何敌人 · 先去闯关击败它们再来斗蛐蛐",
			Vector2(0, 584), Vector2(1280, 26), 15, DIM, HORIZONTAL_ALIGNMENT_CENTER, false)


## 每队人数：红蓝共用一套（同一场里双方人数相等，打起来才公平）
func _build_size_stepper(root: Control) -> void:
	UiKit.label(root, "每队人数", Vector2(946, 18), Vector2(92, 44), 14, DIM,
		HORIZONTAL_ALIGNMENT_RIGHT, false)
	_btn(root, "−", Vector2(1046, 18), Vector2(38, 44), 20, func(): _set_team_size(-1))
	UiKit.label(root, str(_team_size), Vector2(1088, 18), Vector2(44, 44), 20, PAPER,
		HORIZONTAL_ALIGNMENT_CENTER, false)
	_btn(root, "＋", Vector2(1136, 18), Vector2(38, 44), 20, func(): _set_team_size(1))


func _build_card(root: Control, x: float, is_red: bool) -> void:
	var color := RED_COLOR if is_red else BLUE_COLOR
	var stats: Dictionary = _red_stats if is_red else _blue_stats
	var ids: Array = _red_ids if is_red else _blue_ids

	var card := ColorRect.new()
	card.color = Color(0.03, 0.03, 0.03, 0.55)
	card.position = Vector2(x, CARD_Y)
	card.size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	UiKit.rule(root, Vector2(x, CARD_Y), Vector2(CARD_W, 3), Color(color.r, color.g, color.b, 0.75))

	UiKit.label(root, "红 队" if is_red else "蓝 队", Vector2(x, CARD_Y + 8), Vector2(CARD_W, 36), 26,
		color, HORIZONTAL_ALIGNMENT_CENTER, false)
	UiKit.label(root, _team_title(ids), Vector2(x, CARD_Y + 46), Vector2(CARD_W, 30), 21, PAPER,
		HORIZONTAL_ALIGNMENT_CENTER, false)
	UiKit.label(root, "已选 %d / %d · 满员后点新人会顶掉最后一位" % [ids.size(), _team_size],
		Vector2(x, CARD_Y + 76), Vector2(CARD_W, 18), 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, false)

	for i in _roster.size():
		var row := i / CHIP_COLS
		var col := i % CHIP_COLS
		var id := str(_roster[i]["id"])
		var order := ids.find(id)
		_chip(root, _roster[i], Vector2(
			x + 20.0 + float(col) * (CHIP_W + CHIP_GAP),
			CARD_Y + GRID_TOP + float(row) * (CHIP_H + CHIP_GAP)),
			order, color, is_red)

	UiKit.rule(root, Vector2(x + 20, CARD_Y + STAT_TOP - 8), Vector2(CARD_W - 40, 1), Color(1, 1, 1, 0.10))
	for i in STAT_ROWS.size():
		var row2 := i / 2
		var col2 := i % 2
		_stat_cell(root, Vector2(
			x + 20.0 + float(col2) * (STAT_W + 12.0),
			CARD_Y + STAT_TOP + float(row2) * (STAT_H + 6.0)),
			STAT_ROWS[i], float(stats.get(str(STAT_ROWS[i]["key"]), 0.0)), is_red, color)


## 名录格：选中 = 按下的墨牌 + 队伍色字 + 底部队色线 + 左上角出场序号，未选 = 常态墨牌压暗。
## 图鉴里不存在的解锁角色只占位显示「不可用·未知」，按钮禁用，不能选中。
func _chip(root: Control, e: Dictionary, pos: Vector2, order: int, color: Color, is_red: bool) -> void:
	var id := str(e["id"])
	var available := bool(e.get("available", true))
	var selected := available and order >= 0
	var b := UiKit.texture_button(root, str(e["name"]), pos, Vector2(CHIP_W, CHIP_H),
		15 if available else 12,
		color if selected else (DIM if available else UNKNOWN_COLOR),
		func(): _toggle(is_red, id),
		UiKit.BTN_PRESSED if selected else UiKit.BTN_NORMAL)
	if not available:
		b.disabled = true
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW
	b.modulate = Color(1, 1, 1, 1) if selected else Color(0.95, 0.95, 0.95, 0.55)
	if not available:
		b.modulate = Color(0.72, 0.72, 0.72, 0.38)
	if selected:
		UiKit.rule(root, Vector2(pos.x + 8, pos.y + CHIP_H - 3), Vector2(CHIP_W - 16, 2), color)
		UiKit.label(root, str(order + 1), pos + Vector2(5, 2), Vector2(16, 16), 12, color,
			HORIZONTAL_ALIGNMENT_LEFT, false)


func _stat_cell(root: Control, pos: Vector2, row: Dictionary, value: float, is_red: bool, color: Color) -> void:
	var key := str(row["key"])
	var step := float(row["step"])
	var plate := ColorRect.new()
	plate.color = Color(1, 1, 1, 0.05)
	plate.position = pos + Vector2(0, 2)
	plate.size = Vector2(STAT_W, STAT_H - 4)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)
	UiKit.label(root, str(row["label"]), pos + Vector2(0, 0), Vector2(62, STAT_H), 15, DIM,
		HORIZONTAL_ALIGNMENT_LEFT, false)
	_btn(root, "−", pos + Vector2(64, 8), Vector2(38, 42), 20,
		func(): _adjust(is_red, key, -step))
	UiKit.label(root, stat_text(key, value), pos + Vector2(106, 0), Vector2(84, STAT_H), 17, color,
		HORIZONTAL_ALIGNMENT_CENTER, false)
	_btn(root, "＋", pos + Vector2(194, 8), Vector2(38, 42), 20,
		func(): _adjust(is_red, key, step))


# ============================ 观战 ============================

func _build_battle(root: Control) -> void:
	UiKit.label(root, "V S", Vector2(596, HUD_TOP + 6), Vector2(88, 28), 17, DIM,
		HORIZONTAL_ALIGNMENT_CENTER, false)
	for i in MAX_TEAM:
		_rows_red.append(_hud_row(root, i, true))
		_rows_blue.append(_hud_row(root, i, false))
	UiKit.label(root, "自动对战中 · 只可观战", Vector2(0, 644), Vector2(1280, 24), 14, DIM,
		HORIZONTAL_ALIGNMENT_CENTER, false)
	_btn(root, "返  回", Vector2(1100, 650), Vector2(124, 44), 18, func(): back_requested.emit())


func _hud_row(root: Control, i: int, is_red: bool) -> Control:
	var color := RED_COLOR if is_red else BLUE_COLOR
	var row := Control.new()
	row.position = Vector2(0, HUD_TOP + float(i) * HUD_ROW_H)
	row.size = Vector2(1280, HUD_ROW_H - 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(row)

	var lbl := UiKit.label(row, "", Vector2(40 if is_red else 1050, 0), Vector2(HUD_LBL_W, 30), 15,
		color, HORIZONTAL_ALIGNMENT_RIGHT if is_red else HORIZONTAL_ALIGNMENT_LEFT, false)

	var box := ColorRect.new()
	box.color = Color(1, 1, 1, 0.12)
	box.position = Vector2(HUD_BAR_X + (0.0 if is_red else 500.0), 9)
	box.size = Vector2(HUD_BAR_W, 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)

	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2(HUD_BAR_X + (0.0 if is_red else 500.0), 10)
	fill.size = Vector2(HUD_BAR_W, 12)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)

	row.set_meta("fill", fill)
	row.set_meta("lbl", lbl)
	row.visible = false
	return row


# ============================ 结算 ============================

func _build_result(root: Control) -> void:
	UiKit.label(root, _result_text, Vector2(0, 150), Vector2(1280, 84), 48, _result_color,
		HORIZONTAL_ALIGNMENT_CENTER, false)
	UiKit.label(root, "数值由沙盒面板设定 · 换一组再战", Vector2(0, 242), Vector2(1280, 26), 15, DIM,
		HORIZONTAL_ALIGNMENT_CENTER, false)
	_btn(root, "再 来 一 局", Vector2(414, 292), Vector2(200, 54), 20, _rematch)
	_btn(root, "换 组 合", Vector2(666, 292), Vector2(200, 54), 20, _to_config)
	_btn(root, "返  回", Vector2(56, 28), Vector2(124, 44), 18, func(): back_requested.emit())


# ============================ 公共 ============================

func _btn(parent: Node, text: String, pos: Vector2, size: Vector2, font_size: int, cb: Callable) -> TextureButton:
	return UiKit.texture_button(parent, text, pos, size, font_size, PAPER, func():
		_sfx.stream = SFX_CLICK
		_sfx.play()
		cb.call())


func _entry(id: String) -> Dictionary:
	for e in _roster:
		if str(e["id"]) == id:
			return e
	return _roster[0] if not _roster.is_empty() else {}


func _team_title(ids: Array) -> String:
	var names: Array = []
	for id in ids:
		names.append(str(_entry(str(id))["name"]))
	return " · ".join(names)


func stat_text(key: String, v: float) -> String:
	match key:
		"hp", "spd":
			return "%d" % int(round(v))
		"atk":
			return "×%.1f" % v
		_:
			return "%.1fs" % v


## 点名录：已选 → 取消（至少留一个）；未选 → 加入，满员就顶掉最后一位。
## 图鉴里不存在的角色不允许进入队伍。
func _toggle(is_red: bool, id: String) -> void:
	if not Roster.is_unlocked(id):
		return
	var ids: Array = _red_ids if is_red else _blue_ids
	if ids.has(id):
		if ids.size() <= 1:
			return
		ids.erase(id)
	else:
		if ids.size() >= _team_size:
			ids.remove_at(ids.size() - 1)
		ids.append(id)
	_refresh()


func _set_team_size(delta: int) -> void:
	_team_size = clampi(_team_size + delta, 1, MAX_TEAM)
	for arr in [_red_ids, _blue_ids]:
		while arr.size() > _team_size:
			arr.remove_at(arr.size() - 1)
	_refresh()


func _adjust(is_red: bool, key: String, delta: float) -> void:
	var stats: Dictionary = _red_stats if is_red else _blue_stats
	var lo := 0.0
	var hi := 9999.0
	for r in STAT_ROWS:
		if str(r["key"]) == key:
			lo = float(r["min"])
			hi = float(r["max"])
	var v := clampf(float(stats.get(key, lo)) + delta, lo, hi)
	if key == "atk" or key == "gap":
		v = snappedf(v, 0.1)
	else:
		v = roundf(v)
	stats[key] = v
	_refresh()


## 出战前过滤：只留下图鉴内存在的角色；整队都被过滤空时回落为名录第一个可用角色。
func _sanitize(ids: Array) -> Array:
	var out: Array = Roster.available_ids(ids)
	if not out.is_empty():
		return out
	for e in _roster:
		if bool(e.get("available", false)):
			out.append(str(e["id"]))
			break
	return out


func _start_battle() -> void:
	_red_ids = _sanitize(_red_ids)
	_blue_ids = _sanitize(_blue_ids)
	if _red_ids.is_empty() or _blue_ids.is_empty():
		return # 图鉴未收录任何可用敌人时不允许开局
	_sfx.stream = SFX_DECIDE
	_sfx.play()
	_mode = "battle"
	start_requested.emit(_red_ids.duplicate(), _blue_ids.duplicate(),
		_red_stats.duplicate(), _blue_stats.duplicate())
	_refresh()


func _rematch() -> void:
	_mode = "battle"
	rematch_requested.emit()
	_refresh()


func _to_config() -> void:
	_mode = "config"
	config_requested.emit() # 让场景把上一局的两只清掉，别留着倒地的尸体当背景
	_refresh()
