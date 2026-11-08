extends CanvasLayer

## 触屏控件布局编辑层：全屏遮罩上按真实位置画出摇杆与四键，直接拖拽摆放。
## 保存时把归一化坐标交回设置面板（同时立即落盘并生效），取消则完全丢弃。

signal saved(layout: Dictionary)
signal cancelled

const TouchLayout = preload("res://scripts/ui/touch_layout.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.76, 0.73, 0.66)
const RED := Color(0.66, 0.20, 0.17)
const GOLD := Color(0.91, 0.75, 0.34)


## 画布：负责绘制与拖拽（按钮是它的子节点，会先吃掉自己的点击）
class Board extends Control:
	var editor # 反向引用 touch_layout_editor.gd

	func _draw() -> void:
		editor.draw_board(self)

	func _gui_input(event: InputEvent) -> void:
		editor.handle_gui(event)


var _board: Board
var _space := Rect2()
var _layout: Dictionary = {}
var _drag_id := ""
var _drag_off := Vector2.ZERO


## 打开前调用：传入当前布局
func setup(layout: Dictionary) -> void:
	_layout = TouchLayout.sanitize(layout)


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_space = TouchLayout.safe_space()
	_layout = TouchLayout.sanitize(_layout)

	_board = Board.new()
	_board.editor = self
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_board)

	UiKit.label(_board, "调 整 控 件 位 置", Vector2(_space.position.x, _space.position.y + 14),
		Vector2(_space.size.x, 40), 26, PAPER, HORIZONTAL_ALIGNMENT_CENTER, false)
	UiKit.label(_board, "拖动摇杆或按键摆放位置 · 保存后立即生效", Vector2(_space.position.x, _space.position.y + 54),
		Vector2(_space.size.x, 24), 15, DIM, HORIZONTAL_ALIGNMENT_CENTER, false)

	var cx := _space.get_center().x
	var by := _space.end.y - 64.0
	UiKit.texture_button(_board, "恢复默认", Vector2(cx - 330.0, by), Vector2(190, 50), 20, PAPER, _reset)
	UiKit.texture_button(_board, "取  消", Vector2(cx - 110.0, by), Vector2(190, 50), 20, PAPER, _cancel)
	UiKit.texture_button(_board, "保  存", Vector2(cx + 110.0, by), Vector2(190, 50), 20, GOLD, _save)


# Esc / 返回手势由设置面板统一处理（先关编辑层、不关面板），这里不再重复监听，
# 否则父子两层都会响应同一次按键，可能出现「编辑层和设置面板一起关掉」。


# ---------- 绘制 ----------

func draw_board(board: Control) -> void:
	var full := board.get_viewport_rect()
	board.draw_rect(Rect2(Vector2.ZERO, full.size), Color(0, 0, 0, 0.66), true)
	board.draw_rect(_space, Color(PAPER, 0.22), false, 2.0)

	var font := board.get_theme_default_font()
	var stick_c := TouchLayout.center(_layout, "stick", _space)
	var stick_r := TouchLayout.radius("stick")
	board.draw_circle(stick_c, stick_r, Color(0.03, 0.03, 0.03, 0.45))
	board.draw_arc(stick_c, stick_r, 0.0, TAU, 48, Color(PAPER, 0.55), 2.0, true)
	board.draw_circle(stick_c, 30.0, Color(PAPER, 0.5))
	board.draw_arc(stick_c, 30.0, 0.0, TAU, 32, Color(PAPER, 0.85), 2.0, true)

	for id in ["attack", "jump", "dash", "skill"]:
		var c := TouchLayout.center(_layout, id, _space)
		var r := TouchLayout.radius(id)
		var dragging: bool = _drag_id == str(id)
		board.draw_circle(c, r, Color(RED, 0.55) if dragging else Color(0.03, 0.03, 0.03, 0.5))
		board.draw_arc(c, r, 0.0, TAU, 40, Color(GOLD if dragging else PAPER, 0.9), 2.0, true)
		_text_centered(board, font, c, str(TouchLayout.BUTTON_TEXT.get(id, "")), 22, PAPER)

	if _drag_id != "":
		var c2 := TouchLayout.center(_layout, _drag_id, _space)
		board.draw_arc(c2, TouchLayout.radius(_drag_id) + 10.0, 0.0, TAU, 40, Color(GOLD, 0.55), 2.0, true)


func _text_centered(board: Control, font: Font, center: Vector2, text: String, size: int, color: Color) -> void:
	if font == null or text == "":
		return
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var asc := font.get_ascent(size)
	board.draw_string(font, Vector2(center.x - w * 0.5, center.y + asc * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


# ---------- 拖拽 ----------

func handle_gui(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var phase := 0 # 1 按下 / 2 拖动 / 3 抬起
	if event is InputEventScreenTouch:
		pos = event.position
		phase = 1 if event.pressed else 3
	elif event is InputEventScreenDrag:
		pos = event.position
		phase = 2
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		phase = 1 if event.pressed else 3
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		pos = event.position
		phase = 2
	else:
		return
	if phase == 1:
		_drag_id = TouchLayout.hit_any(_layout, pos, _space, 1.5)
		if _drag_id != "":
			_drag_off = TouchLayout.center(_layout, _drag_id, _space) - pos
		else:
			_drag_off = Vector2.ZERO
		_board.queue_redraw()
	elif phase == 3:
		if _drag_id != "":
			_layout = TouchLayout.clamped_layout(_layout, _space)
			_drag_id = ""
			_board.queue_redraw()
	elif _drag_id != "":
		var c := TouchLayout.clamp_center(pos + _drag_off, _drag_id, _space)
		_layout[_drag_id] = TouchLayout.normalize(c, _space)
		_board.queue_redraw()
	_board.accept_event()


# ---------- 按钮 ----------

func _reset() -> void:
	_drag_id = ""
	_layout = TouchLayout.default_layout()
	_board.queue_redraw()


func _save() -> void:
	_layout = TouchLayout.clamped_layout(_layout, _space)
	saved.emit(_layout.duplicate(true))
	_close()


func _cancel() -> void:
	cancelled.emit()
	_close()


func _close() -> void:
	set_process_input(false)
	queue_free()
