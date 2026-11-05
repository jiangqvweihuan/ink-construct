extends Node2D

## 伤害飘字：上移淡出后自动销毁。
## 用法：new() 后立刻 setup(文本, 颜色[, 伤害值])，再 add_child 到场景根。
## 第三参数为伤害值；传入负数表示状态/提示类飘字，不受「伤害数字」档位限制。

const Settings = preload("res://scripts/ui/settings.gd")

var _text := ""
var _color := Color.WHITE
var _magnitude := -1
var _t := 0.0
var _life := 0.7


func setup(text: String, color: Color, magnitude := -1) -> void:
	_text = text
	_color = color
	_magnitude = magnitude


func _ready() -> void:
	if not _visible_by_setting(_magnitude):
		queue_free()
		return
	var l := Label.new()
	l.text = _text
	l.add_theme_color_override("font_color", _color)
	l.add_theme_font_size_override("font_size", 24)
	l.position = Vector2(-8, 0)
	l.z_index = 50
	add_child(l)


func _process(delta: float) -> void:
	_t += delta
	position.y -= 46.0 * delta
	modulate.a = clampf(1.0 - _t / _life, 0.0, 1.0)
	if _t >= _life:
		queue_free()


## 0 关闭 / 1 仅重击（≥3）/ 2 全部显示；提示类飘字始终保留。
static func _visible_by_setting(magnitude: int) -> bool:
	if magnitude < 0:
		return true
	match int(Settings.damage_numbers):
		0:
			return false
		1:
			return magnitude >= 3
		_:
			return true
