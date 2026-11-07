extends Control

## 手势层绘制：浮动摇杆、墨环、右上角暂停键。纯绘制，不接收输入。

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
var view_size := Vector2(1280, 720)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	_draw_pause()
	if wheel_visible:
		_draw_wheel()


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
