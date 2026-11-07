extends CanvasLayer

## 手机操作教程：首次进入战斗时静音文字太多的问题，这里单独用一张大卡片讲清触摸手势。
## 只给触屏版显示；卡片期间暂停整棵树，读完点「知道了」继续战斗。

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")

const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.72, 0.69, 0.62)
const RED := Color(0.78, 0.30, 0.24)
const GOLD := Color(0.91, 0.75, 0.34)

const WIN_POS := Vector2(240, 52)
const WIN_SIZE := Vector2(800, 616)

## 同一次启动只看一次：换房间重载场景也不会反复弹
static var seen := false

## 教程条目：手势 → 作用。设置面板「操作」页手机端复用这份文案
const ROWS := [
	["左半屏 · 左右拖动", "移动"],
	["右半屏 · 点按", "攻击"],
	["右半屏 · 向上划", "跳跃"],
	["右半屏 · 左右横划", "闪避"],
	["右半屏 · 长按", "打开墨环，拖动选招式，松手释放"],
	["右上角墨牌", "暂停 / 设置 / 退出"],
	["从屏幕边缘内滑", "弹出退出确认，不会直接退出"],
]

var _was_paused := false
var _closed := false


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	UiKit.fit_layer(self, [dim])

	var win := TextureRect.new()
	win.texture = InkTex.load("res://art/ui/menu/window_large.png")
	win.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	win.stretch_mode = TextureRect.STRETCH_SCALE
	win.position = WIN_POS
	win.size = WIN_SIZE
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(win)

	UiKit.label(self, "手机操作", WIN_POS + Vector2(0, 26), Vector2(WIN_SIZE.x, 46), 30, PAPER,
		HORIZONTAL_ALIGNMENT_CENTER, false)
	UiKit.rule(self, WIN_POS + Vector2(120, 84), Vector2(WIN_SIZE.x - 240.0, 2), Color(RED, 0.55))
	UiKit.label(self, "战斗只需两只手：左手管走位，右手管出手", WIN_POS + Vector2(0, 96),
		Vector2(WIN_SIZE.x, 28), 16, DIM, HORIZONTAL_ALIGNMENT_CENTER, false)

	var y := 146.0
	for row in ROWS:
		UiKit.label(self, str(row[0]), WIN_POS + Vector2(48, y), Vector2(300, 40), 21, GOLD,
			HORIZONTAL_ALIGNMENT_RIGHT, false)
		UiKit.label(self, str(row[1]), WIN_POS + Vector2(372, y), Vector2(392, 40), 19, PAPER,
			HORIZONTAL_ALIGNMENT_LEFT, false)
		y += 52.0

	UiKit.label(self, "暂停键在右上角，随时可以看状态、改设置或回主菜单。",
		WIN_POS + Vector2(0, 512), Vector2(WIN_SIZE.x, 26), 15, Color(DIM, 0.9),
		HORIZONTAL_ALIGNMENT_CENTER, false)

	UiKit.texture_button(self, "知道了", WIN_POS + Vector2(290, 544), Vector2(220, 56), 22, PAPER, _close)


func _input(event: InputEvent) -> void:
	if _closed:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
		return
	# 轻点任意处也关掉；只在按下时处理，避免划动手势误触
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if _closed:
		return
	_closed = true
	get_tree().paused = _was_paused
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(s)
	s.stream = SFX_CLICK
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)
	queue_free()
