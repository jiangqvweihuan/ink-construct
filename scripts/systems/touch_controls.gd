extends Node

## 移动端手势层：左半屏浮动摇杆，右半屏点按 / 上划 / 横划 / 长按墨环。
## 只在 Android（或命令行 --touch-preview）启用，桌面键鼠路径完全不受影响。
## 所有动作都通过 Input.action_press 注入 InputMap，战斗代码无需改动。

const OVERLAY_SCRIPT = preload("res://scripts/ui/touch_overlay.gd")
const BattleStatus = preload("res://scripts/ui/battle_status.gd")

const MOVE_ZONE_W := 0.45 # 移动区：左侧 45% 宽度，隐形，只在按下时生效
const MOVE_ZONE_TOP := 96.0 # 避开顶部状态栏，留出上沿
const MOVE_RANGE := 92.0 # 拖到该距离即满速
const MOVE_DEAD := 0.16 # 摇杆死区（按比例）
const TAP_SLOP := 26.0 # 判定为点按的最大位移
const TAP_TIME := 0.24 # 判定为点按的最长时间
const LONG_PRESS := 0.30 # 长按开墨环的时间
const SWIPE_MIN := 70.0 # 触发划动的距离
const WHEEL_MIN := 36.0 # 墨环内选中扇区的最小拖动距离
const TAP_HOLD := 0.09 # 虚拟按键按住时长，保证 just_pressed 被物理帧读到

enum Hand { NONE, PENDING, WHEEL, FIRED }

## 供 HUD 判断是否显示手势标识
var active := false

var _preview := false
var _layer: CanvasLayer
var _overlay # 绘制层（touch_overlay.gd），动态取属性，故不标注 Control 类型

# 左手摇杆
var _move_id := -1
var _move_origin := Vector2.ZERO
var _move_pos := Vector2.ZERO
var _moving := false
var _stick_mute := 0.0

# 右手手势
var _act_id := -1
var _act_start := Vector2.ZERO
var _act_pos := Vector2.ZERO
var _act_time := 0.0
var _act_mode := Hand.NONE
var _wheel_sel := -1
var _wheel_labels: Array[String] = []
var _wheel_actions: Array[String] = []
var _wheel_locked: Array[bool] = []

var _taps: Array = []
var _hint_time := 9.0


func _ready() -> void:
	_preview = OS.get_cmdline_args().has("--touch-preview")
	active = OS.has_feature("mobile") or _preview
	if not active:
		set_process(false)
		set_process_unhandled_input(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 4
	add_child(_layer)
	_overlay = OVERLAY_SCRIPT.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_overlay)


func _view() -> Rect2:
	return get_viewport().get_visible_rect()


func _pause_rect() -> Rect2:
	var v := _view().size
	return Rect2(v.x - 100.0, 12.0, 84.0, 46.0)


func _player() -> Node:
	var list := get_tree().get_nodes_in_group("player")
	return null if list.is_empty() else list[0]


func _battle_active() -> bool:
	return not get_tree().get_nodes_in_group("player").is_empty()


## 移动区：左下固定的一块隐形区域，不做自由摇杆
func _in_move_zone(pos: Vector2) -> bool:
	var v := _view().size
	return pos.x < v.x * MOVE_ZONE_W and pos.y > MOVE_ZONE_TOP


# ---------- 主循环 ----------

func _process(delta: float) -> void:
	_tick_taps(delta)
	if _stick_mute > 0.0:
		_stick_mute = maxf(0.0, _stick_mute - delta)
		if _stick_mute <= 0.0 and _moving:
			_sync_move()
	var live := active and _battle_active() and not get_tree().paused
	if _act_id >= 0:
		_act_time += delta
		if live and _act_mode == Hand.PENDING and _act_time >= LONG_PRESS \
				and _act_start.distance_to(_act_pos) <= TAP_SLOP:
			_open_wheel()
	if live:
		_hint_time = maxf(0.0, _hint_time - delta)
	else:
		_cancel_gestures()
	_sync_overlay(live)


func _sync_overlay(live: bool) -> void:
	if _overlay == null:
		return
	_overlay.visible = live
	if not live:
		return
	_overlay.wheel_visible = _act_mode == Hand.WHEEL
	_overlay.wheel_center = _act_start
	_overlay.wheel_labels = _wheel_labels
	_overlay.wheel_locked = _wheel_locked
	_overlay.wheel_sel = _wheel_sel
	_overlay.pause_rect = _pause_rect()
	_overlay.hint = _hint_time > 0.0
	_overlay.view_size = _view().size
	_overlay.queue_redraw()


# ---------- 输入 ----------

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	var idx := -1
	var pos := Vector2.ZERO
	var phase := 0 # 1 按下 / 2 拖动 / 3 抬起
	if event is InputEventScreenTouch:
		idx = event.index
		pos = event.position
		phase = 1 if event.pressed else 3
	elif event is InputEventScreenDrag:
		idx = event.index
		pos = event.position
		phase = 2
	elif _preview and event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		idx = 0
		pos = event.position
		phase = 1 if event.pressed else 3
	elif _preview and event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			return
		idx = 0
		pos = event.position
		phase = 2
	else:
		return
	if not _battle_active() or get_tree().paused:
		return
	if phase == 1 and not _view().has_point(pos):
		return
	var used := false
	if phase == 1:
		used = _start(pos, idx)
	elif phase == 2:
		used = _drag(pos, idx)
	else:
		used = _release(idx)
	if used:
		get_viewport().set_input_as_handled()


func _start(pos: Vector2, idx: int) -> bool:
	if _pause_rect().has_point(pos):
		_push_cancel()
		return true
	if _in_move_zone(pos):
		if _move_id >= 0:
			return false
		_move_id = idx
		_move_origin = pos
		_move_pos = pos
		_moving = true
		_stick_mute = 0.0
		_sync_move()
		return true
	if _act_id >= 0:
		return false
	_act_id = idx
	_act_start = pos
	_act_pos = pos
	_act_time = 0.0
	_act_mode = Hand.PENDING
	_wheel_sel = -1
	return true


func _drag(pos: Vector2, idx: int) -> bool:
	if idx == _move_id:
		_move_pos = pos
		_sync_move()
		return true
	if idx == _act_id:
		_drag_hand(pos)
		return true
	return false


func _release(idx: int) -> bool:
	if idx == _move_id:
		_end_move()
		return true
	if idx == _act_id:
		_end_hand()
		return true
	return false


# ---------- 摇杆 ----------

func _sync_move() -> void:
	_release_move()
	if _stick_mute > 0.0 or not _moving:
		return
	var dx := (_move_pos - _move_origin).x / MOVE_RANGE
	if absf(dx) < MOVE_DEAD:
		return
	if dx < 0.0:
		Input.action_press("move_left", 1.0)
	else:
		Input.action_press("move_right", 1.0)


func _release_move() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")


func _end_move() -> void:
	_move_id = -1
	_moving = false
	_release_move()


# ---------- 右手手势 ----------

func _drag_hand(pos: Vector2) -> void:
	_act_pos = pos
	var d := pos - _act_start
	if _act_mode == Hand.WHEEL:
		_update_wheel(d)
		return
	if _act_mode != Hand.PENDING or d.length() < TAP_SLOP:
		return
	if absf(d.x) >= absf(d.y):
		if absf(d.x) >= SWIPE_MIN:
			_act_mode = Hand.FIRED
			_swipe_dash(1 if d.x > 0.0 else -1)
	elif -d.y >= SWIPE_MIN:
		_act_mode = Hand.FIRED
		_tap("jump")


func _end_hand() -> void:
	if _act_mode == Hand.WHEEL:
		if _wheel_sel >= 0 and _wheel_sel < _wheel_actions.size():
			if not _wheel_locked[_wheel_sel]:
				_tap(_wheel_actions[_wheel_sel])
	elif _act_mode == Hand.PENDING:
		if _act_time <= TAP_TIME and _act_start.distance_to(_act_pos) <= TAP_SLOP:
			_tap("attack")
	_act_id = -1
	_act_mode = Hand.NONE
	_wheel_sel = -1


## 横划闪避：闪避方向取 facing，先转身并短暂停掉摇杆，避免同方向输入把它拉回去。
func _swipe_dash(dir: int) -> void:
	var p := _player()
	if p != null:
		p.set("facing", dir)
		if p.has_method("_apply_facing"):
			p.call("_apply_facing")
	_stick_mute = 0.12
	_release_move()
	_tap("dash")


# ---------- 墨环 ----------

func _open_wheel() -> void:
	_act_mode = Hand.WHEEL
	_wheel_sel = -1
	_wheel_labels.clear()
	_wheel_actions.clear()
	_wheel_locked.clear()
	var p := _player()
	if p == null:
		return
	var skills = p.get("hud_skills")
	if not (skills is Array):
		return
	var all_cfg = p.get("skill_config")
	for i in skills.size():
		var sid := str(skills[i])
		var cfg: Dictionary = {}
		if all_cfg is Dictionary:
			cfg = all_cfg.get(sid, {})
		var action := str(cfg.get("action", ""))
		_wheel_labels.append(BattleStatus.skill_name(p, i))
		_wheel_actions.append(action)
		var locked := action == "" or BattleStatus.skill_lock(p, sid) != "" \
			or BattleStatus.skill_cooldown(p, sid) > 0.05
		_wheel_locked.append(locked)


func _update_wheel(d: Vector2) -> void:
	var n := _wheel_labels.size()
	if n == 0 or d.length() < WHEEL_MIN:
		_wheel_sel = -1
		return
	var ang := fposmod(atan2(d.y, d.x) + PI * 0.5, TAU)
	_wheel_sel = int(round(ang / TAU * float(n))) % n


# ---------- 虚拟按键 ----------

func _tap(action: String) -> void:
	if action == "":
		return
	Input.action_press(action)
	_taps.append([action, TAP_HOLD])


func _tick_taps(delta: float) -> void:
	for i in range(_taps.size() - 1, -1, -1):
		_taps[i][1] -= delta
		if _taps[i][1] <= 0.0:
			Input.action_release(_taps[i][0])
			_taps.remove_at(i)


## 合成 ui_cancel，复用 room_01 / pause_menu 现有的暂停逻辑。
func _push_cancel() -> void:
	_push_cancel_deferred.call_deferred()


func _push_cancel_deferred() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	get_viewport().push_input(ev)


func _cancel_gestures() -> void:
	if _move_id >= 0:
		_end_move()
	if _act_id >= 0:
		_act_id = -1
		_act_mode = Hand.NONE
		_wheel_sel = -1
