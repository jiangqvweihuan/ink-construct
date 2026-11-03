extends Control

const InkTex = preload("res://scripts/ui/ink_tex.gd")

## 共用生命条：红色当前生命、白色掉血残影、绿色回血提前量、右端白色额外防护。
## 额外生命仍保留在 hp 中；护盾/格挡由 extra 传入，不侵入基础生命比例。

const VERMILION := Color(0.659, 0.196, 0.165)
const HEAL := Color(0.30, 0.66, 0.39)
const PAPER := Color(0.949, 0.918, 0.847)
const INK := Color(0.05, 0.05, 0.05)

var bar_width := 380.0
var bar_height := 30.0
var extra_width_cap := 0.0 # 0 表示不限制；Boss 用预留宽度避免伸进右上状态区。
var hp := 0
var max_hp := 1
var extra := 0
var _external_extra := 0

var _red_clip: Control
var _white_clip: Control
var _green_clip: Control
var _extra_root: Control
var _extra_back: ColorRect
var _extra_clip: Control
var _extra_ticks: Control
var _extra_label: Label
var _red_tween: Tween
var _white_tween: Tween
var _last_hp := -1
var _last_max := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(bar_width, bar_height)
	_texture("res://art/ui/hud/hp_empty.png", self, Vector2.ZERO, Vector2(bar_width, bar_height), Color.WHITE)
	_green_clip = _clip(HEAL)
	_white_clip = _clip(PAPER)
	_red_clip = _clip(VERMILION)
	_texture("res://art/ui/hud/hp_frame.png", self, Vector2.ZERO, Vector2(bar_width, bar_height), Color.WHITE)
	_build_extra()


func _texture(path: String, parent: Control, pos: Vector2, dimensions: Vector2, tint: Color) -> TextureRect:
	var t := TextureRect.new()
	t.texture = InkTex.load(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.position = pos
	t.size = dimensions
	t.modulate = tint
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


func _clip(tint: Color) -> Control:
	var c := Control.new()
	c.clip_contents = true
	c.size = Vector2(0, bar_height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	_texture("res://art/ui/hud/bar_white_full.png", c, Vector2.ZERO, Vector2(bar_width, bar_height), tint)
	return c


func _build_extra() -> void:
	_extra_root = Control.new()
	_extra_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extra_root.visible = false
	add_child(_extra_root)
	_extra_back = ColorRect.new()
	_extra_back.color = Color(INK, 0.78)
	_extra_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extra_root.add_child(_extra_back)
	_extra_clip = Control.new()
	_extra_clip.clip_contents = true
	_extra_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extra_root.add_child(_extra_clip)
	_texture("res://art/ui/hud/bar_white_full.png", _extra_clip, Vector2.ZERO, Vector2(bar_width, bar_height), PAPER)
	_extra_ticks = Control.new()
	_extra_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extra_root.add_child(_extra_ticks)
	_extra_label = Label.new()
	_extra_label.add_theme_font_size_override("font_size", 13)
	_extra_label.add_theme_color_override("font_color", PAPER)
	_extra_label.add_theme_color_override("font_outline_color", INK)
	_extra_label.add_theme_constant_override("outline_size", 4)
	_extra_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extra_root.add_child(_extra_label)


## instant 用于首次挂载与换房，避免开场把初始化误播成回血。
func set_vital(new_hp: int, new_max_hp: int, new_extra := 0, instant := false) -> void:
	new_max_hp = maxi(1, new_max_hp)
	new_hp = maxi(0, new_hp)
	new_extra = maxi(0, new_extra)
	_external_extra = new_extra
	var base_hp := mini(new_hp, new_max_hp)
	var inherent_extra := maxi(0, new_hp - new_max_hp)
	var first := _last_hp < 0 or instant or _last_max != new_max_hp
	var old_base := mini(_last_hp, _last_max) if _last_hp >= 0 else base_hp
	hp = new_hp
	max_hp = new_max_hp
	extra = inherent_extra + new_extra
	if _red_clip == null:
		_last_hp = hp
		_last_max = max_hp
		return
	if _red_tween != null and _red_tween.is_valid():
		_red_tween.kill()
	if _white_tween != null and _white_tween.is_valid():
		_white_tween.kill()
	if first:
		_set_width(_red_clip, base_hp)
		_set_width(_white_clip, base_hp)
		_set_width(_green_clip, base_hp)
	elif base_hp < old_base:
		# 掉血：红条立即到目标，白色残影停留片刻再追上。
		_set_width(_red_clip, base_hp)
		_set_width(_green_clip, base_hp)
		_set_width(_white_clip, old_base)
		_white_tween = create_tween()
		_white_tween.tween_interval(0.28)
		_white_tween.tween_method(func(v: float): _set_width(_white_clip, v), float(old_base), float(base_hp), 0.46) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	elif base_hp > old_base:
		# 回血：绿色先到目标，红色与旧白底一起缓慢涨上去。
		_set_width(_green_clip, base_hp)
		_set_width(_red_clip, old_base)
		_set_width(_white_clip, old_base)
		_red_tween = create_tween()
		_red_tween.set_parallel(true)
		_red_tween.tween_method(func(v: float): _set_width(_red_clip, v), float(old_base), float(base_hp), 0.38) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_red_tween.tween_method(func(v: float): _set_width(_white_clip, v), float(old_base), float(base_hp), 0.38) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_set_width(_red_clip, base_hp)
		_set_width(_white_clip, base_hp)
		_set_width(_green_clip, base_hp)
	_last_hp = hp
	_last_max = max_hp
	_update_extra()


## 完全格挡可能不发 hp_changed，HUD 用这个接口单独同步防护尾段。
func set_extra(new_extra: int) -> void:
	new_extra = maxi(0, new_extra)
	if new_extra == _external_extra:
		return
	_external_extra = new_extra
	extra = maxi(0, hp - max_hp) + new_extra
	_update_extra()


func _set_width(c: Control, value: float) -> void:
	c.size.x = bar_width * clampf(value / float(maxi(1, max_hp)), 0.0, 1.0)


func _update_extra() -> void:
	if _extra_root == null:
		return
	_extra_root.visible = extra > 0
	if extra <= 0:
		size.x = bar_width
		return
	var unit := bar_width / float(maxi(1, max_hp))
	var full_w := maxf(8.0, unit * float(extra))
	var tail_w := minf(full_w, extra_width_cap) if extra_width_cap > 0.0 else full_w
	_extra_root.position = Vector2(bar_width + 5.0, 0)
	_extra_root.size = Vector2(tail_w, bar_height)
	_extra_back.position = Vector2(-2, -1)
	_extra_back.size = Vector2(tail_w + 4, bar_height + 2)
	_extra_clip.size = Vector2(tail_w, bar_height)
	for c in _extra_ticks.get_children():
		c.queue_free()
	var tick_step := unit if is_equal_approx(tail_w, full_w) else tail_w / float(extra)
	if tick_step >= 3.0:
		for i in range(1, extra):
			var tick := ColorRect.new()
			tick.color = Color(INK, 0.34)
			tick.position = Vector2(tick_step * float(i), 3)
			tick.size = Vector2(1, bar_height - 6)
			tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_extra_ticks.add_child(tick)
	_extra_label.text = "+%d" % extra
	_extra_label.position = Vector2(4, -1)
	_extra_label.size = Vector2(maxf(30, tail_w), bar_height)
	_extra_label.visible = tail_w >= 30.0
	size.x = bar_width + 5.0 + tail_w
