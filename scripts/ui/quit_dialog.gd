extends CanvasLayer

## 退出确认：安卓滑动返回 / 桌面关窗 / 主菜单「退出」统一走这里，避免一滑就秒退。
## 弹出时暂停整棵树（含战斗），按 Esc 或再次返回手势等于取消，恢复打开前的暂停状态。

signal confirmed
signal cancelled

const InkTex = preload("res://scripts/ui/ink_tex.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const SFX_CLICK := preload("res://audio/sfx/click.wav")
const SFX_BACK := preload("res://audio/sfx/ui_back.wav")

const PAPER := Color(0.949, 0.918, 0.847)
const DIM := Color(0.72, 0.69, 0.62)
const RED := Color(0.78, 0.30, 0.24)

const WIN_POS := Vector2(320, 170)
const WIN_SIZE := Vector2(640, 380)

var _was_paused := false
var _closed := false


func _ready() -> void:
	layer = 110 # 高于加载遮罩（100），转场途中也能看见确认框
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
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

	UiKit.label(self, "退  出", WIN_POS + Vector2(0, 26), Vector2(WIN_SIZE.x, 50), 30, PAPER,
		HORIZONTAL_ALIGNMENT_CENTER, false)
	UiKit.rule(self, WIN_POS + Vector2(120, 88), Vector2(WIN_SIZE.x - 240.0, 2), Color(RED, 0.55))
	UiKit.label(self, "确定要离开《墨构》吗？", WIN_POS + Vector2(0, 110), Vector2(WIN_SIZE.x, 34), 21, PAPER,
		HORIZONTAL_ALIGNMENT_CENTER, false)
	UiKit.label(self, "返回可继续游玩，退出将直接关闭游戏。", WIN_POS + Vector2(0, 148), Vector2(WIN_SIZE.x, 28), 15, DIM,
		HORIZONTAL_ALIGNMENT_CENTER, false)

	UiKit.texture_button(self, "继续游玩", WIN_POS + Vector2(70, 236), Vector2(220, 60), 22, PAPER, cancel)
	UiKit.texture_button(self, "退出游戏", WIN_POS + Vector2(350, 236), Vector2(220, 60), 22, RED, _confirm)


func _input(event: InputEvent) -> void:
	if _closed or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	cancel()


## 取消：恢复打开前的暂停状态并关掉弹窗
func cancel() -> void:
	if _closed:
		return
	_closed = true
	get_tree().paused = _was_paused
	_play_sfx(SFX_BACK)
	cancelled.emit()
	queue_free()


func _confirm() -> void:
	if _closed:
		return
	_closed = true
	_play_sfx(SFX_CLICK)
	confirmed.emit()


func _play_sfx(stream: AudioStream) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(s)
	s.stream = stream
	s.play()
	s.finished.connect(s.queue_free, CONNECT_ONE_SHOT)
