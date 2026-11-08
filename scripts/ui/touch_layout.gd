extends RefCounted

## 触屏控件布局：安全区换算 / 归一化存取 / 命中判定，全部收在这一份里。
## 绘制（touch_overlay）、输入（touch_controls）、设置与编辑（settings / touch_layout_editor）
## 共用同一套换算，避免出现「画在这里、判在那里」的位置偏移。

const IDS := ["stick", "attack", "jump", "dash", "skill"]

## 控件半径（逻辑像素：720 高度固定，天然跨分辨率等比）
const RADIUS := {
	"stick": 68.0, "attack": 44.0, "jump": 44.0, "dash": 44.0, "skill": 50.0,
}

## 默认布局（相对安全区的归一化坐标）：左下摇杆，右下四键错落排布
const DEFAULT_LAYOUT := {
	"stick": Vector2(0.14, 0.76),
	"attack": Vector2(0.88, 0.80),
	"jump": Vector2(0.95, 0.68),
	"dash": Vector2(0.79, 0.72),
	"skill": Vector2(0.87, 0.60),
}

## 按键单字（绘制用）
const BUTTON_TEXT := {"attack": "攻", "jump": "跳", "dash": "闪", "skill": "技"}


static func default_layout() -> Dictionary:
	return DEFAULT_LAYOUT.duplicate()


## 可交互区域（逻辑坐标）：手机全屏时扣掉刘海/圆角，其余情况就是整块可视区。
## 桌面与窗口化必须回退到 visible_rect，否则安全区是屏幕像素，会整体偏移。
static func safe_space() -> Rect2:
	var ml := Engine.get_main_loop()
	var vp: Viewport = (ml as SceneTree).root if ml is SceneTree else null
	if vp == null:
		return Rect2(Vector2.ZERO, Vector2(1280, 720))
	var full := vp.get_visible_rect()
	if not OS.has_feature("mobile"):
		return full
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		return full
	var px := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return full
	# 物理像素 -> 逻辑坐标：与拉伸比例一致（keep_height 下等比缩放）
	var k := full.size.y / float(win.y)
	var pos := Vector2(float(px.position.x) * k, float(px.position.y) * k)
	var sz := Vector2(float(px.size.x) * k, float(px.size.y) * k)
	if sz.x < 64.0 or sz.y < 64.0:
		return full
	return Rect2(full.position + pos, sz)


static func radius(id: String) -> float:
	return float(RADIUS.get(id, 44.0))


## 归一化坐标 -> 实际中心点
static func center(layout: Dictionary, id: String, space: Rect2) -> Vector2:
	var n: Vector2 = layout.get(id, DEFAULT_LAYOUT.get(id, Vector2(0.5, 0.5)))
	return space.position + Vector2(n.x * space.size.x, n.y * space.size.y)


## 实际中心点 -> 归一化坐标
static func normalize(pos: Vector2, space: Rect2) -> Vector2:
	return Vector2(
		(pos.x - space.position.x) / maxf(space.size.x, 1.0),
		(pos.y - space.position.y) / maxf(space.size.y, 1.0))


## 把中心点限制在安全区内（控件完整可见）
static func clamp_center(c: Vector2, id: String, space: Rect2) -> Vector2:
	var r := radius(id) + 4.0
	return Vector2(
		clampf(c.x, space.position.x + r, space.end.x - r),
		clampf(c.y, space.position.y + r, space.end.y - r))


static func hit(layout: Dictionary, id: String, pos: Vector2, space: Rect2, scale := 1.0) -> bool:
	return center(layout, id, space).distance_to(pos) <= radius(id) * scale


## 命中最靠近的手指元素（编辑层拖拽用），缩放放宽便于点到
static func hit_any(layout: Dictionary, pos: Vector2, space: Rect2, scale := 1.5) -> String:
	var best := ""
	var best_d := INF
	for id in IDS:
		var d := center(layout, id, space).distance_to(pos)
		if d <= radius(id) * scale and d < best_d:
			best = str(id)
			best_d = d
	return best


## 清洗存档数据：缺项补默认、越界钳制、脏类型丢弃
static func sanitize(data: Variant) -> Dictionary:
	var out := default_layout()
	if not (data is Dictionary):
		return out
	for id in IDS:
		var v: Variant = (data as Dictionary).get(id, null)
		if v is Vector2:
			out[id] = Vector2(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0))
		elif v is Vector2i:
			out[id] = Vector2(clampf(float(v.x), 0.0, 1.0), clampf(float(v.y), 0.0, 1.0))
	return out


## 把布局按当前安全区钳制后写回归一化坐标（拖动结束时用）
static func clamped_layout(layout: Dictionary, space: Rect2) -> Dictionary:
	var out := {}
	for id in IDS:
		var c := clamp_center(center(layout, id, space), id, space)
		out[id] = normalize(c, space)
	return out
