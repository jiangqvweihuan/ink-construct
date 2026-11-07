## 面板共用控件工厂：文字 / 墨牌按钮 / 分隔线。
## 各面板保留自己的薄包装函数，样式与行为统一在这里改。
## 用法：const UiKit = preload("res://scripts/ui/ui_kit.gd")


const InkTex = preload("res://scripts/ui/ink_tex.gd")

const BTN_NORMAL := "res://art/ui/menu/btn_normal.png"
const BTN_PRESSED := "res://art/ui/menu/btn_clicked.png"


## 一行居中文字；wrap=true 时按框宽自动换行（中文长句用），false 时不换行
static func label(
	parent: Node,
	text: String,
	pos: Vector2,
	size: Vector2,
	font_size: int,
	color: Color,
	align := HORIZONTAL_ALIGNMENT_CENTER,
	wrap := true
) -> Label:
	var l := Label.new()
	l.text = text
	# 必须先开 autowrap 再设 size：否则 size 会被「整行文字宽度」这个最小尺寸顶回去，
	# 传进来的窄宽度失效，长文字直接溢出容器。
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## 墨牌按钮：底图 + 居中文字 + 点击回调
static func texture_button(
	parent: Node,
	text: String,
	pos: Vector2,
	size: Vector2,
	font_size: int,
	color: Color,
	cb: Callable,
	normal := BTN_NORMAL,
	pressed := BTN_PRESSED
) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = InkTex.load(normal)
	b.texture_pressed = InkTex.load(pressed)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = size
	b.position = pos
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	label(b, text, Vector2.ZERO, size, font_size, color, HORIZONTAL_ALIGNMENT_CENTER, false)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## 细分隔线
static func rule(parent: Node, pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


## ---------- 超宽画布（手机 20:9）适配 ----------
## 手机用 stretch/aspect=keep_height，逻辑画布比 1280 更宽（20:9 时 1600×720）。
## 按 1280×720 绝对坐标排版的整层 UI 会整体偏左，这里把整层右移 (画布宽-1280)/2 让它视觉居中。
## bleed 传铺满全屏的节点（淡幕/黑底），会被反向拉回，保证仍然覆盖整个画布。

static func wide_offset(parent: Node) -> float:
	var vp := parent.get_viewport()
	if vp == null:
		return 0.0
	# 已经在做过偏移的 CanvasLayer 里（例如暂停菜单里再打开设置），父层已经居中过，不再重复偏移
	var p := parent.get_parent()
	while p != null:
		if p is CanvasLayer:
			return 0.0
		p = p.get_parent()
	return maxf(0.0, (vp.get_visible_rect().size.x - 1280.0) * 0.5)


## CanvasLayer 版：整层 offset 右移；bleed 里的全屏节点反向补偿，避免左侧露出缝。
static func fit_layer(layer: CanvasLayer, bleed: Array = []) -> void:
	var dx := wide_offset(layer)
	layer.offset = Vector2(dx, 0.0)
	for n in bleed:
		if n is Control and is_instance_valid(n):
			var c := n as Control
			c.offset_left = -dx
			c.offset_right = -dx


## Control 版（铺满全屏的面板）：整个面板右移；bleed 里的全屏节点同样反向补偿。
static func fit_control(panel: Control, bleed: Array = []) -> void:
	var dx := wide_offset(panel)
	panel.position = Vector2(dx, 0.0)
	for n in bleed:
		if n is Control and is_instance_valid(n):
			var c := n as Control
			c.offset_left = -dx
			c.offset_right = -dx
