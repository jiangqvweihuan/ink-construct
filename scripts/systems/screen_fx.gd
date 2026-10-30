extends CanvasLayer

## 全屏亮度叠加层（autoload 名 ScreenFX）：把最终画面按系数乘亮/压暗（0.5~1.5）。
## 亮度 = 1.0 时隐藏叠加层，零开销。layer 100 压在所有场景/UI/CanvasLayer 之上。
## 设置入口：Settings.set_brightness() / apply_all()。

var _mat: ShaderMaterial
var _rect: ColorRect


func _ready() -> void:
	layer = 100
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float brightness : hint_range(0.5, 1.5) = 1.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	COLOR = vec4(clamp(c * brightness, vec3(0.0), vec3(1.0)), 1.0);
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	add_child(_rect)


func set_brightness(v: float) -> void:
	_rect.visible = absf(v - 1.0) > 0.001
	_mat.set_shader_parameter("brightness", v)
