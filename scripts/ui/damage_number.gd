extends Node2D

## 伤害飘字：上移淡出后自动销毁。
## 用法：new() 后立刻 setup(文本, 颜色)，再 add_child 到场景根。

var _text := ""
var _color := Color.WHITE
var _t := 0.0
var _life := 0.7


func setup(text: String, color: Color) -> void:
	_text = text
	_color = color


func _ready() -> void:
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
