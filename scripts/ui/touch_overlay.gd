extends Control

## 手势层绘制：浮动摇杆、墨环、右上角暂停键与首次提示。纯绘制，不接收输入。

const INK := Color(0.05, 0.05, 0.05)
const PAPER := Color(0.949, 0.918, 0.847)
const VERMILION := Color(0.659, 0.196, 0.165)
const DIM := Color(0.76, 0.73, 0.66)
const GOLD := Color(0.91, 0.75, 0.34)

const WHEEL_RADIUS := 148.0
const SECTOR_RADIUS := 26.0
const SECTOR_DIST := 104.0

var wheel_visible := false
var wheel_center := Vector2.ZERO
var wheel_labels: Array[String] = []
var wheel_locked: Array[bool] = []
var wheel_sel := -1

var pause_rect := Rect2()
var hint := false
var view_size := Vector2(1280, 720)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	_draw_pause()
	if wheel_visible:
		_draw_wheel()
	if hint:
		_draw_hint()


func _font() -> Font:
	var f := get_theme_default_font()
	return f if f != null else ThemeDB.fallback_font


func _text_centered(font: Font, center: Vector2, text: String, size: int, color: Color) -> void:
	if font == null or text == "":
		return
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var asc := font.get_ascent(size)
	draw_string(font, Vector2(center.x - w * 0.5, center.y + asc * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


func _draw_pause() -> void:
	if pause_rect.size.x <= 0.0:
		return
	draw_rect(Rect2(pause_rect.position, pause_rect.size), Color(INK, 0.34), true)
	draw_rect(Rect2(pause_rect.position, pause_rect.size), Color(PAPER, 0.5), false, 2.0)
	var c := pause_rect.position + pause_rect.size * 0.5
	draw_rect(Rect2(Vector2(c.x - 9.0, c.y - 9.0), Vector2(6, 18)), Color(PAPER, 0.9), true)
	draw_rect(Rect2(Vector2(c.x + 3.0, c.y - 9.0), Vector2(6, 18)), Color(PAPER, 0.9), true)


func _draw_wheel() -> void:
	draw_circle(wheel_center, WHEEL_RADIUS, Color(0.03, 0.03, 0.03, 0.52))
	draw_arc(wheel_center, WHEEL_RADIUS, 0.0, TAU, 64, Color(PAPER, 0.34), 2.0, true)
	draw_arc(wheel_center, WHEEL_RADIUS - 12.0, 0.0, TAU, 64, Color(VERMILION, 0.5), 1.5, true)
	var font := _font()
	if wheel_labels.is_empty():
		_text_centered(font, wheel_center, "无可用招式", 20, Color(PAPER, 0.7))
		return
	var n := wheel_labels.size()
	for i in n:
		var ang := -PI * 0.5 + TAU * float(i) / float(n)
		var pos := wheel_center + Vector2(cos(ang), sin(ang)) * SECTOR_DIST
		var sel := i == wheel_sel
		var locked: bool = i < wheel_locked.size() and wheel_locked[i]
		var fill := Color(VERMILION, 0.82) if sel else Color(0.04, 0.04, 0.04, 0.70)
		var edge := GOLD if sel else Color(PAPER, 0.38)
		draw_circle(pos, SECTOR_RADIUS, fill)
		draw_arc(pos, SECTOR_RADIUS, 0.0, TAU, 32, edge, 2.0, true)
		var col := Color(PAPER, 0.35) if locked else (PAPER if sel else DIM)
		_text_centered(font, pos, wheel_labels[i], 18, col)


func _draw_hint() -> void:
	# 首次进入战斗的手势提示：深墨底卡片 + 大字，放画面中上部，不贴底边
	var font := _font()
	var lines := [
		"左半屏左右拖动 · 移动",
		"右半屏：点按攻击 · 上划跳跃 · 横划闪避 · 长按开墨环",
	]
	var fsize := 22
	var line_h := font.get_height(fsize)
	var line_gap := 10.0
	var pad := Vector2(34, 22)
	var text_w := 0.0
	for t in lines:
		text_w = maxf(text_w, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize).x)
	var box := Rect2(Vector2.ZERO, Vector2(text_w + pad.x * 2.0,
		line_h * float(lines.size()) + line_gap * float(lines.size() - 1) + pad.y * 2.0))
	box.position = Vector2(view_size.x * 0.5 - box.size.x * 0.5, view_size.y * 0.30)
	draw_rect(box, Color(0.03, 0.03, 0.03, 0.82), true)
	draw_rect(box, Color(PAPER, 0.45), false, 2.0)
	var y := box.position.y + pad.y
	for t in lines:
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize).x
		draw_string(font, Vector2(box.position.x + box.size.x * 0.5 - tw * 0.5, y + font.get_ascent(fsize)),
			t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize, Color(PAPER, 0.98))
		y += line_h + line_gap
