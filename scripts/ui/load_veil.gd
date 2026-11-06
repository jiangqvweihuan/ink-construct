extends CanvasLayer

## 通用加载幕：一卷残页从中间向两侧展开，展开之后才继续做重活。
##
## 用法一（遮挡一次重构建/重加载）：
##     await LoadVeil.cover("正在展卷")
##     ... 同步搭界面 ...
##     await LoadVeil.reveal()
##
## 用法二（切场景）：
##     await LoadVeil.transition_to("res://scenes/world/room_01.tscn", "正在入卷")
##
## 注意：cover() 会等两帧再返回，确保幕布已经真正画到屏幕上，之后的卡顿才被挡住。
##
## HIDDEN 为 true 时幕布整体隐藏：不遮屏、不等待，只保留切场景本身的动作。
## 目前各项加载实测都不卡，先关掉过渡；需要恢复时把 HIDDEN 改回 false 即可。

const HIDDEN := true
const PAPER := Color(0.935, 0.905, 0.835)
const INK := Color(0.055, 0.050, 0.045)
const ROLLER := Color(0.20, 0.165, 0.130)
const MIN_SHOW := 0.46 # 最短停留：避免一格闪一下就消失
const OPEN_TIME := 0.34
const CLOSE_TIME := 0.24
const BAND_H := 128.0
const ROLLER_W := 12.0
const ROLLER_H := 152.0

var _dim: ColorRect
var _band: ColorRect
var _roller_l: ColorRect
var _roller_r: ColorRect
var _text: Label
var _tween: Tween
var _busy := false
var _shown_at := 0.0
var _view := Vector2(1280, 720)


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_view = get_viewport().get_visible_rect().size

	_dim = ColorRect.new()
	_dim.color = Color(INK, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_band = ColorRect.new()
	_band.color = PAPER
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_band)

	_roller_l = _make_roller()
	_roller_r = _make_roller()

	_text = Label.new()
	_text.text = "正\n在\n展\n卷"
	_text.size = Vector2(40, 160)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.add_theme_font_size_override("font_size", 19)
	_text.add_theme_color_override("font_color", INK)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	_layout(0.0)


func _make_roller() -> ColorRect:
	var r := ColorRect.new()
	r.color = ROLLER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


## 展开进度：p 从 0（合卷）到 1（完全展开）
func _layout(p: float) -> void:
	var w := _view.x * p
	var cy := _view.y * 0.5
	_band.position = Vector2((_view.x - w) * 0.5, cy - BAND_H * 0.5)
	_band.size = Vector2(w, BAND_H)
	_roller_l.size = Vector2(ROLLER_W, ROLLER_H)
	_roller_l.position = Vector2(_band.position.x - ROLLER_W * 0.5, cy - ROLLER_H * 0.5)
	_roller_r.size = Vector2(ROLLER_W, ROLLER_H)
	_roller_r.position = Vector2(_band.position.x + w - ROLLER_W * 0.5, cy - ROLLER_H * 0.5)
	_text.position = Vector2(_view.x * 0.5 - 20.0, cy - 80.0)
	_text.modulate.a = clampf((p - 0.35) / 0.45, 0.0, 1.0)
	_dim.color = Color(INK, 0.93 * clampf(p * 2.5, 0.0, 1.0))


## 展开幕布，等卷面完全铺开再返回——之后的重活卡的是主线程，
## 玩家看到的是「一整幅已展开的残卷」，而不是卡在展到一半的动画里。
func cover(text := "正在展卷") -> void:
	if _busy:
		return
	_busy = true
	if HIDDEN:
		await get_tree().process_frame
		return
	_view = get_viewport().get_visible_rect().size # 窗口改过大小也要居中
	_text.text = _vertical(text)
	visible = true
	_layout(0.0)
	_shown_at = Time.get_ticks_msec()
	_kill_tween()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_layout, 0.0, 1.0, OPEN_TIME)
	await _tween.finished


## 收起幕布（自动补足最短停留时间）。
func reveal() -> void:
	if HIDDEN:
		_busy = false
		return
	if not visible:
		return
	var wait := MIN_SHOW - (Time.get_ticks_msec() - _shown_at) / 1000.0
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	_kill_tween()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_method(_layout, 1.0, 0.0, CLOSE_TIME)
	await _tween.finished
	visible = false
	_busy = false


## 幕布落下后切场景，等新场景站住再收起。
func transition_to(path: String, text := "正在入卷") -> void:
	if HIDDEN:
		get_tree().change_scene_to_file(path)
		return
	await cover(text)
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	await reveal()


## 幕布落下后重开当前场景。
func transition_reload(text := "正在入卷") -> void:
	if HIDDEN:
		get_tree().reload_current_scene()
		return
	await cover(text)
	get_tree().reload_current_scene()
	await get_tree().process_frame
	await get_tree().process_frame
	await reveal()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## 幕布小字走竖排：逐字换行，去掉空格。
func _vertical(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.substr(i, 1)
		if c.strip_edges() == "":
			continue
		out += c + "\n"
	return out.strip_edges()


## 幕布期间吞掉输入：按 Esc 不能穿透去关掉底下正准备重建的面板。
func _unhandled_input(event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()
