extends CanvasLayer

## 全屏亮度叠加层（autoload 名 ScreenFX）：把最终画面按系数乘亮/压暗（0.5~1.5）。
## 亮度 = 1.0 时隐藏叠加层，零开销。layer 100 压在所有场景/UI/CanvasLayer 之上。
## 设置入口：Settings.set_brightness() / apply_all()。

const SpineFX := preload("res://scripts/systems/spine_fx.gd")
const MOUSE_CURSOR := preload("res://art/ui/icons/mouse_cursor.png")
const CURSOR_HOTSPOT := Vector2(2, 2)

var _mat: ShaderMaterial
var _rect: ColorRect
var _click_root: Node2D


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_custom_mouse_cursor(MOUSE_CURSOR, Input.CURSOR_ARROW, CURSOR_HOTSPOT)
	Input.set_custom_mouse_cursor(MOUSE_CURSOR, Input.CURSOR_POINTING_HAND, CURSOR_HOTSPOT)
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

	_click_root = Node2D.new()
	_click_root.name = "ClickRoot"
	_click_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_click_root)
	get_tree().scene_changed.connect(_clear_click_fx)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)


func set_brightness(v: float) -> void:
	_rect.visible = absf(v - 1.0) > 0.001
	_mat.set_shader_parameter("brightness", v)


func _process(_delta: float) -> void:
	var mode := Input.MOUSE_MODE_HIDDEN if _in_active_battle() else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode


func _in_active_battle() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == "res://scenes/world/room_01.tscn" and not get_tree().paused


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	# 战斗操作不喷 UI 特效；暂停中的结算 / 升级 / 设置等仍是菜单点击。
	if _in_active_battle():
		return
	var fx := SpineFX.spawn(_click_root, "E54068", event.position, {
		"anim": "action1", "height": 96.0, "center": true, "always": true, "auto_free": true, "z": 50,
	})
	if fx != null:
		fx.name = "MenuClickFX"


func _clear_click_fx() -> void:
	if _click_root == null:
		return
	for child in _click_root.get_children():
		child.queue_free()
